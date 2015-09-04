{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

module Penny.Column where

import Control.Lens
import Control.Monad (join)
import Penny.Amount
import Penny.Arrangement
import Penny.Clatch
import Penny.Commodity
import Penny.Display
import Penny.Popularity
import Penny.Representation
import Penny.Serial
import Penny.Natural
import Penny.Qty
import Penny.Side
import Data.Monoid
import Data.Text (Text)
import qualified Data.Text as X
import Rainbox hiding (background)
import Rainbow
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Penny.Trio
import Penny.Triamt

-- | Load data into this record to make a color scheme that has
-- different colors for debits and credits, with an alternating
-- background for odd- and even-numbered postings.
data Colors = Colors
  { _debit :: Radiant
  , _credit :: Radiant
  , _neutral :: Radiant
  , _nonLinear :: Radiant
  , _notice :: Radiant
  , _oddBackground :: Radiant
  , _evenBackground :: Radiant
  } deriving (Eq, Ord, Show)

makeLenses ''Colors

instance Monoid Colors where
  mempty = Colors
    { _debit = mempty
    , _credit = mempty
    , _neutral = mempty
    , _nonLinear = mempty
    , _notice = mempty
    , _oddBackground = mempty
    , _evenBackground = mempty
    }

  mappend (Colors x0 x1 x2 x3 x4 x5 x6) (Colors y0 y1 y2 y3 y4 y5 y6)
    = Colors (x0 <> y0) (x1 <> y1) (x2 <> y2) (x3 <> y3)
             (x4 <> y4) (x5 <> y5) (x6 <> y6)

data Env = Env
  { _clatch :: Clatch
  , _history :: History
  , _renderer :: Either (Maybe RadCom) (Maybe RadPer)
  , _colors :: Colors
  }

makeLenses ''Env

newtype Column = Column (Env -> Seq Cell)

makeWrapped ''Column

instance Monoid Column where
  mempty = Column (const mempty)
  mappend (Column cx) (Column cy)
    = Column (\a -> (cx a) <> (cy a))


table
  :: History
  -> Either (Maybe RadCom) (Maybe RadPer)
  -> Colors
  -> Seq Column
  -> Seq Clatch
  -> (Seq (Chunk Text))
table hist rend clrs cols cltchs = render . tableByRows $ dataRows
  where
    dataRows = fmap (mkDataRow $) cltchs
    mkDataRow clatch = join . fmap ($ env) . fmap (^. _Wrapped) $ cols
      where
        env = Env clatch hist rend clrs

background :: Env -> Radiant
background env
  | odd i = env ^. colors.oddBackground
  | otherwise = env ^. colors.evenBackground
  where
    i = env ^. clatch.to postFiltset.forward.to naturalToInteger

class Colable a where
  column :: (Clatch -> a) -> Column

-- | Makes a single cell with a Text.
textCell
  :: (Colors -> Radiant)
  -- ^ Selects the foreground color.
  -> Env
  -- ^ The environment
  -> Text
  -- ^ The text to display
  -> Cell
textCell fg env txt = Cell
  { _rows = Seq.singleton . Seq.singleton
      . back (background env) . fore (env ^. colors.to fg)
      . chunk $ txt
  , _horizontal = top
  , _vertical = left
  , _background = background env
  }

instance Colable Text where
  column f = Column $ \env -> Seq.singleton $
    textCell _nonLinear env (f (env ^. clatch))

spaces :: Int -> Column
spaces i = column (const ((X.replicate i . X.singleton $ ' ')))

spaceCell :: Int -> Env -> Cell
spaceCell i env = textCell _nonLinear env
  (X.replicate i . X.singleton $ ' ')

singleCell
  :: Colable a
  => Env
  -> a
  -> Seq Cell
singleCell env a = ($ env) . (^. _Wrapped) $ column (const a)

instance Colable Bool where
  column f = Column cell
    where
      cell env = Seq.singleton $ Cell
        { _rows = Seq.singleton . Seq.singleton
            . back (background env) . fore fg
            . chunk . X.singleton $ char
        , _horizontal = top
        , _vertical = left
        , _background = background env
        }
        where
          (char, fg)
            | f (_clatch env) = ('T', green)
            | otherwise = ('F', red)

instance Colable Integer where
  column f = column (X.pack . show . f)

instance Colable Unsigned where
  column f = column (naturalToInteger . f)

instance Colable a => Colable (Maybe a) where
  column f = Column g
    where
      g env = case f (env ^. clatch) of
        Nothing -> mempty
        Just v -> singleCell env v

sideCell
  :: Env
  -> Maybe Side
  -> Cell
sideCell env maySide = Cell
  { _rows = Seq.singleton . Seq.singleton
      . back (background env) . fore fgColor
      . chunk $ txt
  , _horizontal = top
  , _vertical = left
  , _background = background env
  }
  where
    (fgColor, txt) = case maySide of
      Nothing -> (env ^. colors.neutral, "--")
      Just Debit -> (env ^. colors.debit, "<")
      Just Credit -> (env ^. colors.credit, ">")

commodityCell
  :: Env
  -> Maybe Side
  -> Orient
  -> Commodity
  -> Cell
commodityCell env maySide orient (Commodity cy) = Cell
  { _rows = Seq.singleton . Seq.singleton
      . back (background env) . fore fgColor
      . chunk $ cy
  , _horizontal = top
  , _vertical = vertOrient
  , _background = background env
  }
  where
    fgColor = case maySide of
      Nothing -> env ^. colors.neutral
      Just Debit -> env ^. colors.debit
      Just Credit -> env ^. colors.credit
    vertOrient
      | orient == CommodityOnLeft = right
      | otherwise = left


instance Colable (Maybe Side) where
  column f = Column $ \env ->
    Seq.singleton (sideCell env (f (_clatch env)))

instance Colable Side where
  column f = Column $ \env ->
    Seq.singleton (sideCell env (Just . f . _clatch $ env))

qtyRepAnyRadixMagnitudeCell
  :: Env
  -> QtyRepAnyRadix
  -> Cell
qtyRepAnyRadixMagnitudeCell env qr
  = textCell getColor env
  . X.pack
  . ($ "")
  . display
  . c'NilOrBrimScalarAnyRadix'QtyRepAnyRadix
  $ qr
  where
    getColor = case sideOrNeutral qr of
      Nothing -> _neutral
      Just Debit -> _debit
      Just Credit -> _credit

repNonNeutralNoSideMagnitudeCell
  :: Env
  -> Maybe Side
  -> RepNonNeutralNoSide
  -> Cell
repNonNeutralNoSideMagnitudeCell env maySide rnn
  = textCell getColor env
  . X.pack
  . ($ "")
  . display
  . c'NilOrBrimScalarAnyRadix'RepNonNeutralNoSide
  $ rnn
  where
    getColor = case maySide of
      Nothing -> _neutral
      Just Debit -> _debit
      Just Credit -> _credit

qtyMagnitudeCell
  :: Env
  -> Maybe Commodity
  -- ^ If a commodity is supplied, it is used to better determine how
  -- to render the Qty.
  -> Qty
  -> Cell
qtyMagnitudeCell env mayCy
  = qtyRepAnyRadixMagnitudeCell env
  . repQty ei
  where
    ei = either (Left . Just) (Right . Just)
      . selectGrouper
      . Penny.Popularity.groupers (env ^. history)
      $ mayCy

-- | Creates three columns: one for the side, one for the magnitude,
-- and a space in the middle.

instance Colable QtyRepAnyRadix where
  column f = Column getCells
    where
      getCells env = sideCell env maySide
        <| spaceCell 1 env
        <| qtyRepAnyRadixMagnitudeCell env (f . _clatch $ env)
        <| Seq.empty
        where
          maySide = sideOrNeutral (f . _clatch $ env)

-- | Creates three columns: one for the side, one for the magnitude,
-- and a space in the middle.
instance Colable Qty where
  column f = Column getCells
    where
      getCells env = sideCell env (sideOrNeutral qty)
        <| spaceCell 1 env
        <| qtyMagnitudeCell env Nothing qty
        <| Seq.empty
        where
          qty = f . _clatch $ env

instance Colable Commodity where
  column f = column ((^. _Wrapped) . f)

-- | Creates seven columns:
--
-- 1.  Side
-- 2.  Space
-- 3.  Separate commodity on left
-- 4.  Space (empty if 3 is empty)
-- 5.  Magnitude (with commodity on left or right, if applicable)
-- 6.  Space (empty if 7 is empty)
-- 7.  Separate commodity on right

instance Colable Amount where
  column f = Column getCells
    where
      getCells env
        = side
        <| space1
        <| cyOnLeft
        <| spc4
        <| magWithCy
        <| spc6
        <| cyOnRight
        <| Seq.empty
        where
          Amount cy qty = f (_clatch env)
          side = sideCell env (sideOrNeutral qty)
          hasSpace = spaceBetween (env ^. history) (Just cy)
          orient = orientation (env ^. history) (Just cy)
          (cyOnLeft, spc4, spc6, cyOnRight)
            | not hasSpace = (mempty, mempty, mempty, mempty)
            | orient == CommodityOnLeft =
                ( commodityCell env (sideOrNeutral qty) orient cy
                , space1
                , mempty
                , mempty
                )
            | otherwise =
                ( mempty
                , mempty
                , space1
                , commodityCell env (sideOrNeutral qty) orient cy
                )
          space1 = spaceCell 1 env
          mag = qtyMagnitudeCell env (Just cy) qty
          magWithCy
            | hasSpace = mag
            | orient == CommodityOnLeft = cyCell <> mag
            | otherwise = mag <> cyCell
            where
              cyCell = commodityCell env (sideOrNeutral qty) CommodityOnLeft cy


-- | Creates seven columns:
--
-- 1.  Side
-- 2.  Space
-- 3.  Separate commodity on left
-- 4.  Space (empty if 3 is empty)
-- 5.  Magnitude (with commodity on left or right, if applicable)
-- 6.  Space (empty if 7 is empty)
-- 7.  Separate commodity on right
--
-- Prefers information from the Trio if available; otherwise, uses
-- what's in the Amount.  Makes no attempt to resolve any
-- inconsistencies between the Trio and the Amount; simply prefers
-- what's in the Trio.

instance Colable Triamt where
  column f = Column getCells where
    getCells env
      = side
      <| space1
      <| cyOnLeft
      <| spc4
      <| magWithCy
      <| spc6
      <| cyOnRight
      <| Seq.empty
      where
        space1 = spaceCell 1 env
        Triamt tri amt = f . _clatch $ env
        cy = case tri of
          QC _ c _ -> c
          SC _ c -> c
          UC _ c _ -> c
          C c -> c
          _ -> amt ^. commodity
        sd = case tri of
          QC q _ _ -> sideOrNeutral q
          Q q -> sideOrNeutral q
          SC s _ -> Just s
          S s -> Just s
          _ -> amt ^. qty.to sideOrNeutral
        side = sideCell env sd
        hasSpace = spaceBetween (env ^. history) (Just cy)
        orient = orientation (env ^. history) (Just cy)
        (cyOnLeft, spc4, spc6, cyOnRight)
          | not hasSpace = (mempty, mempty, mempty, mempty)
          | orient == CommodityOnLeft =
              ( commodityCell env sd orient cy
              , space1
              , mempty
              , mempty
              )
          | otherwise =
              ( mempty
              , mempty
              , space1
              , commodityCell env sd orient cy
              )
        grouper = either (Left . Just) (Right . Just)
          . selectGrouper
          . Penny.Popularity.groupers (env ^. history)
          . Just
          $ cy
        magCell = case tri of
          QC q _ _ -> qtyRepAnyRadixMagnitudeCell env q
          Q q -> qtyRepAnyRadixMagnitudeCell env q
          UC rnn _ _ -> repNonNeutralNoSideMagnitudeCell env sd rnn
          U rnn -> repNonNeutralNoSideMagnitudeCell env sd rnn
          _ -> qtyRepAnyRadixMagnitudeCell env
            . repQty grouper . _qty $ amt
        magWithCy
          | hasSpace = magCell
          | orient == CommodityOnLeft = cyCell <> magCell
          | otherwise = magCell <> cyCell
          where
            cyCell = commodityCell env sd CommodityOnLeft cy
