module Penny.NestedMap (
  NestedMap ( NestedMap ),
  unNestedMap,
  empty,
  relabel,
  modifyLabel,
  deepModifyLabel,
  deepRelabel,
  prune) where

import Data.Map ( Map )
import qualified Data.Map as M
import Data.Monoid

data NestedMap k l =
  NestedMap { unNestedMap :: Map k (l, NestedMap k l) }
  deriving Show

instance Functor (NestedMap k) where
  fmap f (NestedMap m) = let
    g (l, s) = (f l, fmap f s)
    in NestedMap $ M.map g m

-- | An empty NestedMap.
empty :: NestedMap k l
empty = NestedMap (M.empty)

-- | Inserts a new label in the top level of a NestedMap. Any existing
-- label at the given key is obliterated and replaced with the given
-- label. If the given key does not already exist, it is created. If
-- the given key already exists, then the existing NestedMaps nested
-- within are not changed. If the given key does not already exist, an
-- empty NestedMap becomes the children for the label.
relabel :: (Ord k) => NestedMap k l -> k -> l -> NestedMap k l
relabel m k l = modifyLabel m k (const l)

-- | Modifies a label in the top level of a NestedMap. The given
-- function is applied to Nothing if the key does not exist, or to
-- Just v if the key does exist. The given function returns the new
-- value for the label. If the given key already exists, then the
-- existing NestedMaps nested within that key are not changed. If the
-- given key does not already exist, an empty NestedMap becomes the
-- children for the label.
modifyLabel ::
  (Ord k)
  => NestedMap k l
  -> k
  -> (Maybe l -> l)
  -> NestedMap k l
modifyLabel (NestedMap m) k g = NestedMap n where
  n = M.alter f k m
  f Nothing = Just (g Nothing, NestedMap M.empty)
  f (Just (oldL, oldM)) = Just (g (Just oldL), oldM)

-- | Helper function for deepModifyLabel. For a given key and function
-- that modifies the label, return the new submap to insert into the
-- given map. Does not actually insert the submap though. That way,
-- deepModifyLabel can then modify the returned submap before
-- inserting it into the mother map with the given label.
newSubmap ::
  (Ord k)
  => NestedMap k l
  -> k
  -> (Maybe l -> l)
  -> (l, NestedMap k l)
newSubmap (NestedMap m) k g = (newL, NestedMap newM) where
  (newL, newM) = case M.lookup k m of
    Nothing -> (g Nothing, M.empty)
    (Just (oldL, (NestedMap oldM))) -> (g (Just oldL), oldM)

-- | Descends through a NestedMap with successive keys in the list. At
-- any given level, if the key given does not already exist, then
-- inserts an empty submap and applies the given label modification
-- function to Nothing to determine the new label. If the given key
-- already does exist, then preserves the existing submap and applies
-- the given label modification function to (Just oldlabel) to
-- determine the new label.
deepModifyLabel ::
  (Ord k)
  => NestedMap k l
  -> [(k, (Maybe l -> l))]
  -> NestedMap k l
deepModifyLabel m [] = m
deepModifyLabel (NestedMap m) ((k, f):vs) = let
  (newL, newM) = newSubmap (NestedMap m) k f
  newM' = deepModifyLabel newM vs
  in NestedMap $ M.insert k (newL, newM') m

-- | Similar to deepModifyLabel, but instead of granting the option of
-- modifying existing labels, the existing label is replaced with the
-- new label.
deepRelabel ::
  (Ord k)
  => NestedMap k l
  -> [(k, l)]
  -> NestedMap k l
deepRelabel m ls = deepModifyLabel m ls' where
  ls' = map (\(k, l) -> (k, const l)) ls

-- | Descends through the NestedMap and selects keys that match the
-- predicate given. Non-matching keys are discarded. Keys that are
-- below the level of the total length of the list are preserved if
-- their parents were preserved.
prune ::
  (Ord k)
  => NestedMap k l
  -> [(k -> Bool)]
  -> NestedMap k l
prune m [] = m
prune (NestedMap m) (p:ps) = let
  m' = M.filterWithKey (\k _ -> p k) m
  m'' = M.map (\(l, im) -> (l, prune im ps)) m'
  in NestedMap m''

{-
cumulativeTotals ::
  (Monoid l)
  => NestedMap k l
  -> NestedMap k l
cumulativeTotals (NestedMap top) = let
  levelTot (l, (NestedMap m)) =
    if M.null m
    then (l, (NestedMap M.empty))
    else let
      l' = mappend l . mconcat . map levelTot . M.elems $ m
      m' = cumulativeTotals (NestedMap m)
      in (l', m')
  in NestedMap (M.map levelTot top)
-}

{-
cumulativeTotals ::
  (Monoid l)
  => NestedMap k l
  -> (l, NestedMap k l)
cumulativeTotals (NestedMap m) =
  if M.null m
  then (mempty, NestedMap M.empty)
  else let
    (l', subs) = M.map cumulativeTotals m
    subTotal = 
    l' = mappend l . mconcat . 
-}

cumulativeTotals ::
  (Monoid l)
  => NestedMap k l
  -> (l, NestedMap k l)
cumulativeTotals (NestedMap m) =
  if M.null m
  then (mempty, NestedMap M.empty)
  else let
    m' = M.map totalTuple m
    l' = mconcat . map fst . M.elems $ m'
    in (l', NestedMap m')

totalTuple ::
  (Monoid l)
  => (l, NestedMap k l)
  -> (l, NestedMap k l)
totalTuple (l, (NestedMap m)) =
  if M.null m
  then (l, (NestedMap M.empty))
  else let
    l' = mappend l . sumSubmap $ (NestedMap m)
    m' = snd . cumulativeTotals $ (NestedMap m)
    in (l', m')

sumSubmap ::
  (Monoid l)
  => NestedMap k l
  -> l
sumSubmap (NestedMap top) =
  if M.null top
  then mempty
  else mconcat . map fst . M.elems $ top
  --else mconcat . M.elems . M.map (\(_, m) -> sumSubmap m) $ top

-- For testing
map1, map2, map3, map4 :: NestedMap Int String
map1 = NestedMap M.empty
map2 = deepRelabel map1 [(5, "hello"), (66, "goodbye"), (777, "yeah")]
map3 = deepRelabel map2 [(6, "what"), (77, "zeke"), (888, "foo")]
map4 = deepModifyLabel map3
       [ (6, (\m -> case m of Nothing -> "new"; (Just s) -> s ++ "new"))
       , (77, (\m -> case m of Nothing -> "new"; (Just s) -> s ++ "more new")) ]
  
  
