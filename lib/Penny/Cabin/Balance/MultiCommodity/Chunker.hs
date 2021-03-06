{-# LANGUAGE OverloadedStrings #-}
-- | Creates the output Chunks for the Balance report for both
-- multi-commodity reports.

module Penny.Cabin.Balance.MultiCommodity.Chunker (
  Row(..),
  rowsToChunks
  ) where


import Control.Applicative
  (Applicative (pure), (<$>), (<*>))
import qualified Penny.Cabin.Meta as Meta
import qualified Penny.Cabin.Row as R
import qualified Penny.Cabin.Scheme as E
import qualified Penny.Lincoln as L
import Data.Monoid (mempty)
import qualified Data.Foldable as Fdbl
import qualified Data.Text as X
import qualified System.Console.Rainbow as Rb

type IsEven = Bool

data Columns a = Columns {
  acct :: a
  , drCr :: a
  , commodity :: a
  , quantity :: a
  } deriving Show

instance Functor Columns where
  fmap f c = Columns {
    acct = f (acct c)
    , drCr = f (drCr c)
    , commodity = f (commodity c)
    , quantity = f (quantity c)
    }

instance Applicative Columns where
  pure a = Columns a a a a
  fn <*> fa = Columns {
    acct = (acct fn) (acct fa)
    , drCr = (drCr fn) (drCr fa)
    , commodity = (commodity fn) (commodity fa)
    , quantity = (quantity fn) (quantity fa)
     }

data PreSpec = PreSpec {
  _justification :: R.Justification
  , _padSpec :: (E.Label, E.EvenOdd)
  , bits :: [Rb.Chunk] }

-- | When given a list of columns, determine the widest row in each
-- column.
maxWidths :: [Columns PreSpec] -> Columns R.Width
maxWidths = Fdbl.foldl' maxWidthPerColumn (pure (R.Width 0))

-- | Applied to a Columns of PreSpec and a Colums of widths, return a
-- Columns that has the wider of the two values.
maxWidthPerColumn ::
  Columns R.Width
  -> Columns PreSpec
  -> Columns R.Width
maxWidthPerColumn w p = f <$> w <*> p where
  f old new = max old ( safeMaximum (R.Width 0)
                        . map (R.Width . sum . map X.length . Rb.text)
                        . bits $ new)
  safeMaximum d ls = if null ls then d else maximum ls

-- | Changes a single set of Columns to a set of ColumnSpec of the
-- given width.
preSpecToSpec ::
  Columns R.Width
  -> Columns PreSpec
  -> Columns R.ColumnSpec
preSpecToSpec ws p = f <$> ws <*> p where
  f width (PreSpec j ps bs) = R.ColumnSpec j width ps bs

resizeColumnsInList :: [Columns PreSpec] -> [Columns R.ColumnSpec]
resizeColumnsInList cs = map (preSpecToSpec w) cs where
  w = maxWidths cs


-- Step 9
widthSpacerAcct :: Int
widthSpacerAcct = 4

widthSpacerDrCr :: Int
widthSpacerDrCr = 1

widthSpacerCommodity :: Int
widthSpacerCommodity = 1

colsToBits
  :: E.Changers
  -> IsEven
  -> Columns R.ColumnSpec
  -> [Rb.Chunk]
colsToBits chgrs isEven (Columns a dc c q) = let
  fillSpec = if isEven
             then (E.Other, E.Even)
             else (E.Other, E.Odd)
  spacer w = R.ColumnSpec j (R.Width w) fillSpec []
  j = R.LeftJustify
  cs = a
       : spacer widthSpacerAcct
       : dc
       : spacer widthSpacerDrCr
       : c
       : spacer widthSpacerCommodity
       : q
       : []
  in R.row chgrs cs

colsListToBits
  :: E.Changers
  -> [Columns R.ColumnSpec]
  -> [[Rb.Chunk]]
colsListToBits chgrs = zipWith f bools where
  f b c = colsToBits chgrs b c
  bools = iterate not True

preSpecsToBits
  :: E.Changers
  -> [Columns PreSpec]
  -> [Rb.Chunk]
preSpecsToBits chgrs =
  concat
  . colsListToBits chgrs
  . resizeColumnsInList

-- | Displays a single account in a Balance report. In a
-- single-commodity report, this account will only be one screen line
-- long. In a multi-commodity report, it might be multiple lines long,
-- with one screen line for each commodity.
data Row = Row
  { indentation :: Int
  -- ^ Indent the account name by this many levels (not by this many
  -- spaces; this number is multiplied by another number in the
  -- Chunker source to arrive at the final indentation amount)

  , accountTxt :: X.Text
    -- ^ Text for the name of the account

  , balances :: [(L.Commodity, L.BottomLine)]
    -- ^ Commodity balances. If this list is empty, dashes are
    -- displayed for the DrCr, Commodity, and Qty.
  }

rowsToChunks
  :: E.Changers
  -> (L.Amount L.Qty -> X.Text)
  -- ^ How to format a balance to allow for digit grouping
  -> [Row]
  -> [Rb.Chunk]
rowsToChunks chgrs fmt =
  preSpecsToBits chgrs
  . rowsToColumns chgrs fmt

rowsToColumns
  :: E.Changers
  -> (L.Amount L.Qty -> X.Text)
  -- ^ How to format a balance to allow for digit grouping

  -> [Row]
  -> [Columns PreSpec]
rowsToColumns chgrs fmt
  = map (mkColumn chgrs fmt)
  . L.serialItems (\ser a -> (Meta.VisibleNum ser, a))


mkColumn
  :: E.Changers
  -> (L.Amount L.Qty -> X.Text)
  -> (Meta.VisibleNum, Row)
  -> Columns PreSpec
mkColumn chgrs fmt (vn, (Row i acctTxt bs)) = Columns ca cd cc cq
  where
    lbl = E.Other
    eo = E.fromVisibleNum vn
    applyFmt = E.getEvenOddLabelValue lbl eo chgrs
    ca = PreSpec R.LeftJustify (lbl, eo) [applyFmt $ Rb.Chunk mempty [txt]]
      where
        txt = X.append indents acctTxt
        indents = X.replicate (indentAmount * max 0 i)
                  (X.singleton ' ')
    cd = PreSpec R.LeftJustify (lbl, eo) cksDrCr
    cc = PreSpec R.RightJustify (lbl, eo) cksCmdty
    cq = PreSpec R.LeftJustify (lbl, eo) cksQty
    (cksDrCr, cksCmdty, cksQty) =
      if null bs
      then balanceChunksEmpty chgrs eo
      else
        let balChks = map (balanceChunks chgrs fmt eo) bs
            cDrCr = map (\(a, _, _) -> a) balChks
            cCmdty = map (\(_, a, _) -> a) balChks
            cQty = map (\(_, _, a) -> a) balChks
        in (cDrCr, cCmdty, cQty)


balanceChunksEmpty
  :: E.Changers
  -> E.EvenOdd
  -> ([Rb.Chunk], [Rb.Chunk], [Rb.Chunk])
balanceChunksEmpty chgrs eo = (dash, dash, dash)
  where
    dash = [E.getEvenOddLabelValue E.Other eo chgrs $ "--"]

balanceChunks
  :: E.Changers
  -> (L.Amount L.Qty -> X.Text)
  -> E.EvenOdd
  -> (L.Commodity, L.BottomLine)
  -> (Rb.Chunk, Rb.Chunk, Rb.Chunk)
balanceChunks chgrs fmt eo (cty, bl) = (chkDc, chkCt, chkQt)
  where
    chkDc = E.bottomLineToDrCr dc eo chgrs
    dc = case bl of
      L.Zero -> Nothing
      L.NonZero c -> Just $ L.colDrCr c
    chkCt = E.bottomLineToCmdty chgrs eo (cty, bl)
    chkQt = E.bottomLineToQty chgrs fmt eo (cty, bl)


indentAmount :: Int
indentAmount = 2

