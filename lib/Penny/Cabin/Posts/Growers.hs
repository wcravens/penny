-- | Calculates cells that "grow to fit." These cells grow to fit the
-- widest cell in the column. No information is ever truncated from
-- these cells (what use is a truncated dollar amount?)
module Penny.Cabin.Posts.Growers (
  growCells, Fields(..), grownWidth,
  eFields, EFields(..), pairWithSpacer) where

import Control.Applicative((<$>), Applicative(pure, (<*>)))
import qualified Data.Foldable as Fdbl
import Data.List (foldl')
import qualified Data.Map as M
import qualified Data.Semigroup as Semi
import Data.Semigroup ((<>))
import qualified Data.Sequence as Seq
import Data.Text (Text, pack, empty)
import qualified Data.Text as X
import qualified Penny.Cabin.Colors as C
import qualified Penny.Cabin.Posts.Colors as PC
import qualified Penny.Cabin.Posts.Options as O
import qualified Penny.Cabin.Posts.Options as Options
import qualified Penny.Cabin.Posts.Fields as F
import qualified Penny.Cabin.Posts.Info as I
import qualified Penny.Cabin.Posts.Info as Info
import qualified Penny.Cabin.Posts.Spacers as S
import qualified Penny.Cabin.Posts.Spacers as Spacers
import qualified Penny.Cabin.Row as R
import qualified Penny.Lincoln as L
import qualified Penny.Lincoln.Queries as Q

-- | Grows the cells that will be GrowToFit cells in the report. First
-- this function fills in all visible cells with text, but leaves the
-- width undetermined. Then it determines the widest line in each
-- column. Finally it adjusts each cell in the column so that it is
-- that maximum width.
--
-- Returns a list of rows, and a Fields holding the width of each
-- cell. Each of these widths will be at least 1; fields that were in
-- the report but that ended up having no width are changed to
-- Nothing.
growCells ::
  Options.T a
  -> [Info.T]
  -> ([Fields (Maybe R.Cell)], Fields (Maybe Int))
growCells o info = (rowsNoZeroes, widthsNoZeroes) where
  cells = justifyCells widths . map (getCells o) $ info
  fieldsInReport = growingFields o
  widths = measureWidest fieldsInReport cells
  widthsNoZeroes = fmap removeZero widths where
    removeZero maybeI = case maybeI of
      Nothing -> Nothing
      Just 0 -> Nothing
      Just x -> Just x
  fieldsNoZeroes = removeZero <$> widths where
    removeZero width maybeCell = case width of
      Nothing -> Nothing
      Just _ -> maybeCell
  rowsNoZeroes = map (fieldsNoZeroes <*>) cells


-- | Given a width and a cell, resizes the cell.
resizer :: Int -> R.Cell -> R.Cell
resizer i c = c { R.width = C.Width i }

-- | Given measurements of the widest cell in a column, adjusts each
-- cell so that it is that wide.
justifyCells ::
  Fields (Maybe Int)
  -> [Fields (Maybe R.Cell)]
  -> [Fields (Maybe R.Cell)]
justifyCells widths cs = let
  justifier mayWidth mayCell = resizer <$> mayWidth <*> mayCell
  justifyRow = justifier <$> widths
  in map (justifyRow <*>) cs

-- | Measures all cells and returns a Fields indicating the widest
-- field in each column. Fields that are not in the report are
-- Nothing. Fields that are in the report, but that have no width, are
-- Just 0.
measureWidest ::
  Fields Bool
  -> [Fields (Maybe R.Cell)]
  -> Fields (Maybe Int)
measureWidest fs = foldl' updateWidest z where
  z = initWidest fs


-- | Initializes the starting set of fields for the initializer value
-- that is used for updateWidest. Fields that are present in the
-- report are initialized to Just zero; fields not in the report are
-- initialized to Nothing.
initWidest :: Fields Bool -> Fields (Maybe Int)
initWidest = fmap (\b -> if b then Just 0 else Nothing)
  
-- | Given a Fields indicating the cell widths found so far, update
-- the cell widths with values from a new set of cells, keeping
-- whichever is wider. If a cell is not present in the report at all,
-- its corresponding field should be initialized to Nothing; this
-- function will then skip it.
updateWidest ::
  Fields (Maybe Int)
  -> Fields (Maybe R.Cell)
  -> Fields (Maybe Int)
updateWidest fi fc = wider <$> fi <*> fc where
  wider maybeI maybeC =
    max
    <$> maybeI
    <*> ((C.unWidth . R.widestLine . R.chunks) <$> maybeC)
  

getCells :: Options.T a -> Info.T -> Fields (Maybe R.Cell)
getCells os i = let
  flds = growingFields os
  ifShown fld fn = if fld then Just $ fn os i else Nothing
  in ifShown <$> flds <*> growers

-- | Makes a left justified cell that is only one line long. The width
-- is unset.
oneLine :: Text -> Options.T a -> Info.T -> R.Cell
oneLine t os i = let
  bc = Options.baseColors os
  vn = I.visibleNum i
  ts = PC.colors vn bc
  w = C.Width 0
  j = R.LeftJustify
  chunk = Seq.singleton . C.chunk ts $ t
  in R.Cell j w ts chunk

growers :: Fields (Options.T a -> Info.T -> R.Cell)
growers = Fields {
  postingNum = getPostingNum
  , visibleNum = getVisibleNum
  , revPostingNum = getRevPostingNum
  , lineNum = getLineNum
  , date = getDate
  , flag = getFlag
  , number = getNumber
  , postingDrCr = getPostingDrCr
  , postingCmdty = getPostingCmdty
  , postingQty = getPostingQty
  , totalDrCr = getTotalDrCr
  , totalCmdty = getTotalCmdty
  , totalQty = getTotalQty }

getPostingNum :: Options.T a -> Info.T -> R.Cell
getPostingNum os i = oneLine t os i where
  t = pack . show . I.unPostingNum . I.postingNum $ i

getVisibleNum :: Options.T a -> Info.T -> R.Cell
getVisibleNum os i = oneLine t os i where
  t = pack . show . I.unVisibleNum . I.visibleNum $ i

getRevPostingNum :: Options.T a -> Info.T -> R.Cell
getRevPostingNum os i = oneLine t os i where
  t = pack . show . I.unRevPostingNum . I.revPostingNum $ i

getLineNum :: Options.T a -> Info.T -> R.Cell
getLineNum os i = oneLine t os i where
  lineTxt = pack . show . L.unLine . L.unPostingLine
  t = maybe empty lineTxt (Q.postingLine . I.postingBox $ i)

getDate :: Options.T a -> Info.T -> R.Cell
getDate os i = oneLine t os i where
  t = O.dateFormat os i

getFlag :: Options.T a -> Info.T -> R.Cell
getFlag os i = oneLine t os i where
  t = maybe empty L.text (Q.flag . I.postingBox $ i)

getNumber :: Options.T a -> Info.T -> R.Cell
getNumber os i = oneLine t os i where
  t = maybe empty L.text (Q.number . I.postingBox $ i)

dcTxt :: L.DrCr -> Text
dcTxt L.Debit = pack "Dr"
dcTxt L.Credit = pack "Cr"

getPostingDrCr :: Options.T a -> Info.T -> R.Cell
getPostingDrCr os i = oneLine t os i where
  t = dcTxt . Q.drCr . I.postingBox $ i

getPostingCmdty :: Options.T a -> Info.T -> R.Cell
getPostingCmdty os i = oneLine t os i where
  t = L.text . L.Delimited (X.singleton ':') 
      . L.textList . Q.commodity . I.postingBox $ i

getPostingQty :: Options.T a -> Info.T -> R.Cell
getPostingQty os i = oneLine t os i where
  t = O.qtyFormat os i

getTotalDrCr :: Options.T a -> Info.T -> R.Cell
getTotalDrCr os i = let
  vn = I.visibleNum i
  ts = PC.colors vn bc
  bc = PC.drCrToBaseColors dc (O.drCrColors os)
  dc = Q.drCr . I.postingBox $ i
  cs = fmap toChunk
       . Seq.fromList
       . M.elems
       . L.unBalance
       . I.balance
       $ i
  toChunk bl = let
    spec = 
      PC.colors vn
      . PC.bottomLineToBaseColors (O.drCrColors os)
      $ bl
    txt = case bl of
      L.Zero -> pack "--"
      L.NonZero (L.Column clmDrCr _) -> dcTxt clmDrCr
    in C.chunk spec txt
  j = R.LeftJustify
  w = C.Width 0
  in R.Cell j w ts cs

getTotalCmdty :: Options.T a -> Info.T -> R.Cell
getTotalCmdty os i = let
  vn = I.visibleNum i
  j = R.RightJustify
  w = C.Width 0
  ts = PC.colors vn bc
  bc = PC.drCrToBaseColors dc (O.drCrColors os)
  dc = Q.drCr . I.postingBox $ i
  cs = fmap toChunk
       . Seq.fromList
       . M.assocs
       . L.unBalance
       . I.balance
       $ i
  toChunk (com, nou) = let
    spec =
      PC.colors vn
      . PC.bottomLineToBaseColors (O.drCrColors os)
      $ nou
    txt = L.text
          . L.Delimited (X.singleton ':')
          . L.textList
          $ com
    in C.chunk spec txt
  in R.Cell j w ts cs

getTotalQty :: Options.T a -> Info.T -> R.Cell
getTotalQty os i = let
  vn = I.visibleNum i
  j = R.LeftJustify
  ts = PC.colors vn bc
  bc = PC.drCrToBaseColors dc (O.drCrColors os)
  dc = Q.drCr . I.postingBox $ i
  cs = fmap toChunk
       . Seq.fromList
       . M.assocs
       . L.unBalance
       . I.balance
       $ i
  toChunk (com, nou) = let
    spec = 
      PC.colors vn
      . PC.bottomLineToBaseColors (O.drCrColors os)
      $ nou
    txt = O.balanceFormat os com nou
    in C.chunk spec txt
  w = C.Width 0
  in R.Cell j w ts cs

growingFields :: Options.T a -> Fields Bool
growingFields o = let
  f = O.fields o in Fields {
    postingNum = F.postingNum f
    , visibleNum = F.visibleNum f
    , revPostingNum = F.revPostingNum f
    , lineNum = F.lineNum f
    , date = F.date f
    , flag = F.flag f
    , number = F.number f
    , postingDrCr = F.postingDrCr f
    , postingCmdty = F.postingCmdty f
    , postingQty = F.postingQty f
    , totalDrCr = F.totalDrCr f
    , totalCmdty = F.totalCmdty f
    , totalQty = F.totalQty f }

-- | All growing fields, as an ADT.
data EFields =
  EPostingNum
  | EVisibleNum
  | ERevPostingNum
  | ELineNum
  | EDate
  | EFlag
  | ENumber
  | EPostingDrCr
  | EPostingCmdty
  | EPostingQty
  | ETotalDrCr
  | ETotalCmdty
  | ETotalQty
  deriving (Show, Eq, Ord, Enum)

-- | Returns a Fields where each record has its corresponding EField.
eFields :: Fields EFields
eFields = Fields {
  postingNum = EPostingNum
  , visibleNum = EVisibleNum
  , revPostingNum = ERevPostingNum
  , lineNum = ELineNum
  , date = EDate
  , flag = EFlag
  , number = ENumber
  , postingDrCr = EPostingDrCr
  , postingCmdty = EPostingCmdty
  , postingQty = EPostingQty
  , totalDrCr = ETotalDrCr
  , totalCmdty = ETotalCmdty
  , totalQty = ETotalQty }

-- | All growing fields.
data Fields a = Fields {
  postingNum :: a
  , visibleNum :: a
  , revPostingNum :: a
  , lineNum :: a
    -- ^ The line number from the posting's metadata
  , date :: a
  , flag :: a
  , number :: a
  , postingDrCr :: a
  , postingCmdty :: a
  , postingQty :: a
  , totalDrCr :: a
  , totalCmdty :: a
  , totalQty :: a }
  deriving (Show, Eq)

instance Fdbl.Foldable Fields where
  foldr f z i =
    f (postingNum i)
    (f (visibleNum i)
     (f (revPostingNum i)
      (f (lineNum i)
       (f (date i)
        (f (flag i)
         (f (number i)
          (f (postingDrCr i)
           (f (postingCmdty i)
            (f (postingQty i)
             (f (totalDrCr i)
              (f (totalCmdty i)
               (f (totalQty i) z))))))))))))

instance Functor Fields where
  fmap f i = Fields {
    postingNum = f (postingNum i)
    , visibleNum = f (visibleNum i)
    , revPostingNum = f (revPostingNum i)
    , lineNum = f (lineNum i)
    , date = f (date i)
    , flag = f (flag i)
    , number = f (number i)
    , postingDrCr = f (postingDrCr i)
    , postingCmdty = f (postingCmdty i)
    , postingQty = f (postingQty i)
    , totalDrCr = f (totalDrCr i)
    , totalCmdty = f (totalCmdty i)
    , totalQty = f (totalQty i) }

instance Applicative Fields where
  pure a = Fields {
    postingNum = a
    , visibleNum = a
    , revPostingNum = a
    , lineNum = a
    , date = a
    , flag = a
    , number = a
    , postingDrCr = a
    , postingCmdty = a
    , postingQty = a
    , totalDrCr = a
    , totalCmdty = a
    , totalQty = a }

  fl <*> fa = Fields {
    postingNum = postingNum fl (postingNum fa)
    , visibleNum = visibleNum fl (visibleNum fa)
    , revPostingNum = revPostingNum fl (revPostingNum fa)
    , lineNum = lineNum fl (lineNum fa)
    , date = date fl (date fa)
    , flag = flag fl (flag fa)
    , number = number fl (number fa)
    , postingDrCr = postingDrCr fl (postingDrCr fa)
    , postingCmdty = postingCmdty fl (postingCmdty fa)
    , postingQty = postingQty fl (postingQty fa)
    , totalDrCr = totalDrCr fl (totalDrCr fa)
    , totalCmdty = totalCmdty fl (totalCmdty fa)
    , totalQty = totalQty fl (totalQty fa) }
    
-- | Pairs data from a Fields with its matching spacer field. The
-- spacer field is returned in a Maybe because the TotalQty field does
-- not have a spacer.
pairWithSpacer :: Fields a -> Spacers.T b -> Fields (a, Maybe b)
pairWithSpacer f s = Fields {
  postingNum = (postingNum f, Just (S.postingNum s))
  , visibleNum = (visibleNum f, Just (S.visibleNum s))
  , revPostingNum = (revPostingNum f, Just (S.revPostingNum s))
  , lineNum = (lineNum f, Just (S.lineNum s))
  , date = (date f, Just (S.date s))
  , flag = (flag f, Just (S.flag s))
  , number = (number f, Just (S.number s))
  , postingDrCr = (postingDrCr f, Just (S.postingDrCr s))
  , postingCmdty = (postingCmdty f, Just (S.postingCmdty s))
  , postingQty = (postingQty f, Just (S.postingQty s))
  , totalDrCr = (totalDrCr f, Just (S.totalDrCr s))
  , totalCmdty = (totalCmdty f, Just (S.totalCmdty s))
  , totalQty = (totalQty f, Nothing) }

-- | Reduces a set of Fields to a single value.
reduce :: Semi.Semigroup s => Fields s -> s
reduce f =
  postingNum f
  <> visibleNum f
  <> revPostingNum f
  <> lineNum f
  <> date f
  <> flag f
  <> number f
  <> postingDrCr f
  <> postingCmdty f
  <> postingQty f
  <> totalDrCr f
  <> totalCmdty f
  <> totalQty f

-- | Compute the width of all Grown cells, including any applicable
-- spacer cells.
grownWidth ::
  Fields (Maybe Int)
  -> Spacers.T Int
  -> Int
grownWidth fs ss =
  Semi.getSum
  . reduce
  . fmap Semi.Sum
  . fmap fieldWidth
  $ pairWithSpacer fs ss

-- | Compute the field width of a single field and its spacer. The
-- first element of the tuple is the field width, if present; the
-- second element of the tuple is the width of the spacer. If there is
-- no field, returns 0.
fieldWidth :: (Maybe Int, Maybe Int) -> Int
fieldWidth (m1, m2) = case m1 of
  Nothing -> 0
  Just i1 -> case m2 of
    Just i2 -> if i2 > 0 then i1 + i2 else i1
    Nothing -> i1

{-
t_postingNum :: a -> Fields a -> Fields a
t_postingNum a f = f { postingNum = a }

t_visibleNum :: a -> Fields a -> Fields a
t_visibleNum a f = f { visibleNum = a }

t_revPostingNum :: a -> Fields a -> Fields a
t_revPostingNum a f = f { revPostingNum = a }

t_lineNum :: a -> Fields a -> Fields a
t_lineNum a f = f { lineNum = a }

t_date :: a -> Fields a -> Fields a
t_date a f = f { date = a }

t_flag :: a -> Fields a -> Fields a
t_flag a f = f { flag = a }

t_number :: a -> Fields a -> Fields a
t_number a f = f { number = a }

t_postingDrCr :: a -> Fields a -> Fields a
t_postingDrCr a f = f { postingDrCr = a }

t_postingCmdty :: a -> Fields a -> Fields a
t_postingCmdty a f = f { postingCmdty = a }

t_postingQty :: a -> Fields a -> Fields a
t_postingQty a f = f { postingQty = a }

t_totalDrCr :: a -> Fields a -> Fields a
t_totalDrCr a f = f { totalDrCr = a }

t_totalCmdty :: a -> Fields a -> Fields a
t_totalCmdty a f = f { totalCmdty = a }

t_totalQty :: a -> Fields a -> Fields a
t_totalQty a f = f { totalQty = a }

-}
