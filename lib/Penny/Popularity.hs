module Penny.Popularity where

import Control.Lens
import Control.Monad
import Data.Semigroup
import qualified Data.Foldable as F
import Data.Foldable (foldlM)
import qualified Data.Map as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Penny.Amount
import Penny.Commodity
import Penny.Mimode
import Penny.NonEmpty
import Penny.Qty
import Penny.Representation
import Penny.Trio
import Penny.Ledger
import Penny.Converted
import Penny.Transbox
import Penny.Viewpost
import Penny.SeqUtil hiding (rights)
import qualified Penny.SeqUtil


-- | Map describing how different 'Commodity' are rendered.
newtype History = History
  (M.Map Commodity
         (NonEmpty (Arrangement, Either (Seq RadCom) (Seq RadPer))))
  deriving (Eq, Ord, Show)

instance Monoid History where
  mempty = History M.empty
  mappend (History x) (History y) = History $ M.unionWith (<>) x y

-- | Like 'History' but does not include arrangements.
newtype Abridged = Abridged
  (M.Map Commodity (NonEmpty (Either (Seq RadCom) (Seq RadPer))))
  deriving (Eq, Ord, Show)

abridge :: History -> Abridged
abridge (History mp) = Abridged $ fmap (fmap snd) mp

-- | Represents a 'Qty' as \"smartly\" as possible, based on how its
-- corresponding 'Commodity' has been represented in the past.
--
-- In @repQtySmartly ei mp cy qt@, @mp@ is a map of 'Commodity' to
-- consider for history analysis.  Each 'Commodity' is paired with a
-- history list.  Each element of the history list is an 'Either',
-- with a 'Left' indicating that the radix was a comma, and a
-- 'Right' indicating the radix was a period.  The sequence contains
-- each grouping character used.
--
-- If the commodity @cy@ is found in the map @mp@, then the radix
-- point used is always the 'mimode' radix point appearing in the
-- history list.  For that radix point, if there is a 'mimode' grouping
-- character, then grouping is attempted using that grouping
-- character.  If there is no 'mimode' grouping character, no grouping
-- is attempted.
--
-- If the commodity @cy@ is not found in the map @mp@, then the radix
-- point used is the 'mimode' radix point for /all/ commodities in the
-- map @mp@.  For that radix point, if there is a 'mimode' grouping
-- character, then grouping is attempted using that grouping
-- character.  If there is no 'mimode' grouping character, no grouping
-- is attempted.
--
-- If the map @mp@ is completely empty, then the 'Qty' is rendered
-- using @ei@, where @ei@ is @Left Nothing@ for comma radix, no
-- grouping; @Right Nothing@ for period radix, no grouping; @Left
-- (Just c)@ for comma radix with attempted grouping using @c@; or
-- @Right (Just c)@ for period radix with grouping attempted using
-- @c@.
repQtySmartly
  :: Either (Maybe RadCom) (Maybe RadPer)
  -- ^ Default rendering
  -> Abridged
  -- ^ History map
  -> Amount
  -> QtyRepAnyRadix
repQtySmartly dflt (Abridged mp) (Amount cy qty)
  = case repQtyByPopularCommodity mp cy of
  Just f -> f qty
  Nothing -> case map snd . M.assocs $ mp of
    [] -> repQty dflt qty
    x:xs -> repQtyByPopularity (F.foldl' (<>) x xs) qty

-- | Returns a function representing a Qty based on the radix point
-- and grouping character most frequently seen.
repQtyByPopularity
  :: NonEmpty (Either (Seq RadCom) (Seq RadPer))
  -- ^ History list
  -> Qty
  -> QtyRepAnyRadix
repQtyByPopularity = repQty . pickRadix


-- | If possible, returns a function representing a Qty based on the
-- representations that have been seen so far.  @historyRepresent m c@
-- is applied to a map, @m@, which holds all commodities that have
-- been seen with a quantity representation in their respective
-- 'Trio'.  The values in the map are, at minimum, the radix point,
-- and may also contain any grouping characters used.
-- 'historyRepresent' will return a function that renders 'Qty' for
-- that 'Commodity', but only if that 'Commodity' is a key in @m@.
repQtyByPopularCommodity
  :: M.Map Commodity (NonEmpty (Either (Seq RadCom) (Seq RadPer)))
  -- ^ History map
  -> Commodity
  -> Maybe (Qty -> QtyRepAnyRadix)
repQtyByPopularCommodity mp cy = fmap (repQty . pickRadix) (M.lookup cy mp)

-- | Picks the most popular radix point and, if possible, the most
-- popular grouping character corresponding to that radix.
pickRadix
  :: NonEmpty (Either (Seq RadCom) (Seq RadPer))
  -- ^ History list
  -> Either (Maybe RadCom) (Maybe RadPer)
pickRadix ne =
  let NonEmpty rdx _ = modeFromNonEmpty
        . fmap (either (const (Left Radix)) (const (Right Radix)))
        $ ne
  in case rdx of
      Left _ -> Left grpr
        where
          grpr = mimode . mconcat . lefts . seqFromNonEmpty $ ne
      Right _ -> Right grpr
        where
          grpr = mimode . mconcat . rights . seqFromNonEmpty $ ne

lefts :: F.Foldable f => f (Either a b) -> [a]
lefts = F.foldr f []
  where
    f ei acc = case ei of
      Left l -> l : acc
      Right _ -> acc

rights :: F.Foldable f => f (Either a b) -> [b]
rights = F.foldr f []
  where
    f ei acc = case ei of
      Left _ -> acc
      Right r -> r : acc

vote
  :: Ledger l
  => PostingL l
  -> l History
vote = fmap f . trio
  where
    f tri = case trioRendering tri of
      Nothing -> mempty
      Just (cy, ar, ei) -> History
        $ M.singleton cy (NonEmpty (ar, ei) Seq.empty)

elect
  :: Ledger l
  => l History
elect = vault >>= toPostings >>= foldlM f mempty
  where
    toPostings
      = return . join
      <=< traverse postings
      <=< return . join . fmap Penny.SeqUtil.rights
    f acc posting = mappend <$> pure acc <*> vote posting

