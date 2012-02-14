module Penny.Cabin.Postings.Base (
  Allocation,
  unAllocation,
  allocation,
  ColumnWidth(ColumnWidth, unColumnWidth),
  ReportWidth,
  PostingNum,
  unPostingNum,
  CellInfo,
  cellRow,
  cellCol,
  PostingInfo,
  postingNum,
  balance,
  postingBox,
  GrowF,
  AllocateF,
  Column(GrowToFit, Allocate),
  Columns,
  RowsPerPosting,
  unRowsPerPosting,
  rowsPerPosting,
  Queried(EGrowToFit, EAllocate),
  Expanded(Grown, ExAllocate),
  postingsReport) where

import Control.Applicative (pure, (<*>))
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty, toNonEmpty, unsafeToNonEmpty,
                           nonEmpty)
import qualified Data.List.ZipNonEmpty as ZNE
import Data.Map (Map)
import qualified Data.Map as M
import Data.Monoid (mempty, mappend, Monoid)
import Data.Table (
  Table, table, changeColumns, RowNum, ColNum,
  changeRows)
import qualified Data.Table as T
import Data.Traversable (mapAccumL)
import Data.Word (Word)

import Penny.Lincoln.Balance (Balance, entryToBalance)
import Penny.Lincoln.Boxes (PostingBox, PriceBox)
import Penny.Lincoln.Queries (entry)

import Penny.Cabin.Colors (Chunk)
import Penny.Cabin.Postings.Row (Cell)
import qualified Penny.Cabin.Postings.Row as R

data Allocation = Allocation { unAllocation :: Double }
                  deriving Show

newtype ColumnWidth = ColumnWidth { unColumnWidth :: Int }
                   deriving (Show, Eq, Ord)

data ReportWidth = ReportWidth { unReportWidth :: Int }
                   deriving (Show, Eq, Ord)

newtype PostingNum = PostingNum { unPostingNum :: Int }
                     deriving (Show, Eq, Ord)

data CellInfo =
  CellInfo { cellRow :: RowNum
           , cellCol :: ColNum }

data PostingInfo =
  PostingInfo { postingNum :: PostingNum
              , balance :: Balance
              , postingBox :: PostingBox }

type GrowF =
  ReportWidth
  -> [PriceBox]
  -> PostingInfo
  -> CellInfo
  -> (ColumnWidth, Map RowNum Queried -> Cell)

type AllocateF =
  ReportWidth
  -> [PriceBox]
  -> PostingInfo
  -> CellInfo
  -> Map ColNum Expanded
  -> Cell

data Column =
  GrowToFit GrowF
  | Allocate Allocation AllocateF

data Columns = Columns { unColumns :: NonEmpty Column }

newtype RowsPerPosting =
  RowsPerPosting { unRowsPerPosting :: Int }
  deriving Show

data Queried =
  EGrowToFit (ColumnWidth, Map RowNum Queried -> Cell)
  | EAllocate Allocation
    (Map ColNum Expanded -> Cell)

data Expanded =
  Grown Cell
  | ExAllocate Allocation
    (Map ColNum Expanded -> Cell)

rowsPerPosting :: Int -> RowsPerPosting
rowsPerPosting i =
  if i < 1
  then error "rowsPerPosting: must have at least 1 row per posting"
  else RowsPerPosting i

allocation :: Double -> Allocation
allocation d =
  if d > 0
  then Allocation d
  else error "allocations must be greater than zero"

balanceAccum :: Balance -> PostingBox -> (Balance, Balance)
balanceAccum bal pb = (bal', bal') where
  bal' = bal `mappend` pstgBal
  pstgBal = entryToBalance . entry $ pb

balances :: NonEmpty PostingBox
            -> NonEmpty Balance
balances = snd . mapAccumL balanceAccum mempty

postingInfos :: NonEmpty PostingBox
                -> NonEmpty PostingInfo
postingInfos pbs = 
  ZNE.ne
  $ pure PostingInfo
  <*> ZNE.zipNe (pure PostingNum <*> (nonEmpty 0 [1..]))
  <*> ZNE.zipNe (balances pbs)
  <*> ZNE.zipNe pbs
                         
tableToChunk ::
  Table Cell
  -> Chunk
tableToChunk = R.chunk . rows . rowMap . T.unRows . T.unTable

rowMap :: Map T.RowNum (Map T.ColNum Cell)
          -> Map T.RowNum R.Row
rowMap = M.map f where
  f = M.fold R.prependCell R.emptyRow

rows :: Map T.RowNum R.Row
        -> R.Rows
rows = M.fold R.prependRow mempty

postingsReport ::
  ([PostingInfo] -> [PostingInfo])
  -> ReportWidth
  -> Columns
  -> RowsPerPosting
  -> [PriceBox]
  -> [PostingBox]
  -> Maybe Chunk  
postingsReport p rw cols rpp prices pstgs =
  postingsTable p rw cols rpp prices pstgs
  >>= return . tableToChunk

postingsTable ::
  ([PostingInfo] -> [PostingInfo])
  -> ReportWidth
  -> Columns
  -> RowsPerPosting
  -> [PriceBox]
  -> [PostingBox]
  -> Maybe (Table Cell)
postingsTable p rw cols rpp prices pstgs = do
  nePstgs <- toNonEmpty pstgs
  let pis = postingInfos nePstgs
      filtered = p (toList pis)
  neFiltered <- toNonEmpty filtered
  return $
    makeTable rw cols rpp prices neFiltered

makeTable ::
  ReportWidth
  -> Columns
  -> RowsPerPosting
  -> [PriceBox]
  -> NonEmpty PostingInfo
  -> Table Cell
makeTable rw cols rpp prices =
  allocate
  . expand
  . fmap (queried rw prices)
  . cellInfos
  . paired cols rpp

paired ::
  Columns
  -> RowsPerPosting
  -> NonEmpty PostingInfo
  -> Table (PostingInfo, Column)
paired (Columns cs) rpp ps = table (,) (replicatePostings rpp ps) cs

replicatePostings ::
  RowsPerPosting
  -> NonEmpty PostingInfo
  -> NonEmpty PostingInfo
replicatePostings (RowsPerPosting rpp) pis = let
  ls = toList pis
  expanded = concatMap (replicate rpp) ls
  in unsafeToNonEmpty expanded

cellInfos ::
  Table (PostingInfo, Column)
  -> Table (PostingInfo, CellInfo, Column)
cellInfos = changeRows f where
  f rn cn _ (pis, col) = (pis, (CellInfo rn cn), col)

queried ::
  ReportWidth
  -> [PriceBox]
  -> (PostingInfo, CellInfo, Column)
  -> Queried
queried rw pbs (pis, ci, col) = case col of
  GrowToFit f -> EGrowToFit $ f rw pbs pis ci
  Allocate a f -> EAllocate a $ f rw pbs pis ci

expand :: Table Queried -> Table Expanded
expand = changeColumns f where
  f _ _ rm q = case q of
    EGrowToFit (_, grower) -> Grown (grower rm)
    EAllocate a g -> ExAllocate a g

allocate :: Table Expanded -> Table Cell
allocate = changeRows f where
  f _ _ colMap e = case e of
    Grown cs -> cs
    ExAllocate _ g -> g colMap
