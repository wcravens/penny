{-# LANGUAGE DeriveFunctor #-}

-- | Containers for entries.
--
-- This module is the key guardian of the core principle of
-- double-entry accounting, which is that debits and credits must
-- always balance. An 'Ent' is a container for an 'Entry'. An 'Entry'
-- holds a 'DrCr' and an 'Amount' which, in turn, holds a 'Commodity'
-- and a 'Qty'. For a given 'Commodity' in a particular transaction,
-- the sum of the debits must always be equal to the sum of the
-- credits.
--
-- In addition to the 'Entry', the 'Ent' holds information about
-- whether the particular 'Entry' it holds is inferred or not. An Ent
-- is @inferred@ if the user did not supply the entry, but Penny was
-- able to deduce its 'Entry' because proper entries were supplied for
-- all the other postings in the transaction. The 'Ent' also holds
-- arbitrary metadata--which will typically be other information about
-- the particular posting, such as the payee, account, etc.
--
-- A collection of 'Ent' is an 'Ents'. This module will only create an
-- 'Ent' as part of an 'Ents' (though you can later separate the 'Ent'
-- from its other 'Ents' if you like.) In any given 'Ents', all of the
-- 'Ent' collectively have a zero balance.
--
-- This module also contains type synonyms used to represent a
-- Posting, which is an Ent bundled with its sibling Ents, and a
-- Transaction.

module Penny.Lincoln.Ents
  ( -- * Ent
    Ent
  , entry
  , meta
  , inferred

  -- * Ents
  , Ents
  , unEnts
  , tupleEnts
  , mapEnts
  , traverseEnts
  , ents
  , rEnts
  , headEnt
  , tailEnts

  -- * Postings and transactions
  , Posting(..)
  , Transaction(..)
  , transactionToPostings
  , views
  , unrollSnd
  ) where

import Control.Applicative
import Control.Arrow (second)
import qualified Penny.Lincoln.Bits as B
import qualified Penny.Lincoln.Balance as Bal
import Control.Monad (guard)
import qualified Penny.Lincoln.Equivalent as Ev
import Penny.Lincoln.Equivalent ((==~))
import Data.Monoid (mconcat, (<>))
import Data.List (foldl', unfoldr, sortBy)
import Data.Maybe (catMaybes)
import qualified Data.Traversable as Tr
import qualified Data.Foldable as Fdbl


-- | Information about an entry, along with whether it is inferred and
-- its metadata.
data Ent m = Ent
  { entry :: Either (B.Entry B.QtyRep) (B.Entry B.Qty)
  -- ^ The entry from an Ent.  If the Ent is inferred--that is, if the
  -- user did not supply an entry for it and Penny was able to infer
  -- the entry--this will be a Right with the inferred Entry.

  , meta :: m
  -- ^ The metadata accompanying an Ent

  , inferred :: Bool
  -- ^ True if the entry was inferred.
  } deriving (Eq, Ord, Show)

-- | Two Ents are equivalent if the entries are equivalent and the
-- metadata is equivalent (whether the Ent is inferred or not is
-- ignored.)
instance Ev.Equivalent m => Ev.Equivalent (Ent m) where
  equivalent (Ent e1 m1 _) (Ent e2 m2 _) = e1 ==~ e2 && m1 ==~ m2

  compareEv (Ent e1 m1 _) (Ent e2 m2 _) =
    Ev.compareEv e1 e2 <> Ev.compareEv m1 m2

instance Functor Ent where
  fmap f (Ent e m i) = Ent e (f m) i

newtype Ents m = Ents { unEnts :: [Ent m] }
  deriving (Eq, Ord, Show, Functor)

-- | Ents are equivalent if the content Ents of each are
-- equivalent. The order of the ents is insignificant.
instance Ev.Equivalent m => Ev.Equivalent (Ents m) where
  equivalent (Ents e1) (Ents e2) =
    let (e1', e2') = (sortBy Ev.compareEv e1, sortBy Ev.compareEv e2)
    in and $ (length e1 == length e2)
           : zipWith Ev.equivalent e1' e2'

  compareEv (Ents e1) (Ents e2) =
    let (e1', e2') = (sortBy Ev.compareEv e1, sortBy Ev.compareEv e2)
    in mconcat $ compare (length e1) (length e2)
               : zipWith Ev.compareEv e1' e2'

instance Fdbl.Foldable Ents where
  foldr f z (Ents ls) = case ls of
    [] -> z
    x:xs -> f (meta x) (Fdbl.foldr f z (map meta xs))

instance Tr.Traversable Ents where
  sequenceA = fmap Ents . Tr.sequenceA . map seqEnt . unEnts

-- | Alter the metadata Ents, while examining the Ents themselves. If
-- you only want to change the metadata and you don't need to examine
-- the other contents of the Ent, use the Functor instance. You cannot
-- change non-metadata aspects of the Ent.
mapEnts :: (Ent a -> b) -> Ents a -> Ents b
mapEnts f = Ents . map f' . unEnts where
  f' e = e { meta = f e }

-- | Alter the metadata of Ents while examing their contents. If you
-- do not need to examine their contents, use the Traversable
-- instance.
traverseEnts :: Applicative f => (Ent a -> f b) -> Ents a -> f (Ents b)
traverseEnts f = fmap Ents . Tr.traverse f' . unEnts where
  f' en@(Ent e _ i) = Ent <$> pure e <*> f en <*> pure i

seqEnt :: Applicative f => Ent (f a) -> f (Ent a)
seqEnt (Ent e m i) = Ent <$> pure e <*> m <*> pure i

-- | Every Ents alwas contains at least two ents, and possibly
-- additional ones.
tupleEnts :: Ents m -> (Ent m, Ent m, [Ent m])
tupleEnts (Ents ls) = case ls of
  t1:t2:ts -> (t1, t2, ts)
  _ -> error "tupleEnts: ents does not have two ents"

-- | In a Posting, the Ent at the front of the list of Ents is the
-- main posting. There are additional postings. This function
-- rearranges the Ents multiple times so that each posting is at the
-- head of the list exactly once.
views :: Ents m -> [Ents m]
views = map Ents . orderedPermute . unEnts

-- | > unrollSnd (undefined, []) == []
--   > unrollSnd (1, [1,2,3]) = [(1,1), (1,2), (1,3)]

unrollSnd :: (a, [b]) -> [(a, b)]
unrollSnd = unfoldr f where
  f (_, []) = Nothing
  f (a, b:bs) = Just ((a, b), (a, bs))

-- | Splits a Transaction into Postings.
transactionToPostings :: Transaction -> [Posting]
transactionToPostings =
  map Posting . unrollSnd . second views . unTransaction

-- | Get information from the head posting in the View, which is the
-- one you are most likely interested in. This never fails, as every
-- Ents has at least two postings.
headEnt :: Ents m -> Ent m
headEnt (Ents ls) = case ls of
  [] -> error "ents: empty view"
  x:_ -> x

-- | Get information on sibling Ents.
tailEnts :: Ents m -> (Ent m, [Ent m])
tailEnts (Ents ls) = case ls of
  [] -> error "ents: tailEnts: empty view"
  _:xs -> case xs of
    [] -> error "ents: tailEnts: only one sibling"
    s2:ss -> (s2, ss)

-- | A Transaction and a Posting are identical on the inside, but they
-- have different semantic meanings so they are wrapped in newtypes.
newtype Transaction = Transaction
  { unTransaction :: ( B.TopLineData, Ents B.PostingData ) }
  deriving (Eq, Show)

-- | In a Posting, the Ent yielded by 'headEnt' will be the posting of
-- interest. The other sibling postings are also available for
-- inspection.
newtype Posting = Posting
  { unPosting :: ( B.TopLineData, Ents B.PostingData ) }
  deriving (Eq, Show)

-- | Returns a list of lists where each element in the original list
-- is in the front of a new list once.
--
-- > orderedPermute [1,2,3] == [[1,2,3], [2,3,1], [3,1,2]]
orderedPermute :: [a] -> [[a]]
orderedPermute ls = take (length ls) (iterate toTheBack ls)
  where
    toTheBack [] = []
    toTheBack (a:as) = as ++ [a]

-- | Creates an 'Ents'. At most, one of the Maybe Entry can be Nothing
-- and this function will infer the remaining Entry. This function
-- fails if it cannot create a balanced Ents.
ents
  :: [(Maybe (Either (B.Entry B.QtyRep) (B.Entry B.Qty)), m)]
  -> Maybe (Ents m)
ents ls = do
  guard . not . null $ ls
  let nNoEntries = length . filter (== Nothing) . map fst $ ls
  case Bal.entriesToBalanced
       . map (either (fmap B.toQty) id)
       . catMaybes
       . map fst
       $ ls of
    Bal.NotInferable -> Nothing
    Bal.Inferable e -> do
      guard $ nNoEntries == 1
      let makeEnt (mayEn, mt) = case mayEn of
            Nothing -> Ent (Right e) mt True
            Just en -> Ent en mt False
      return . Ents $ map makeEnt ls
    Bal.Balanced ->
      let makeEnt (mayEn, mt) = case mayEn of
            Nothing -> Nothing
            Just en -> Just $ Ent en mt False
      in fmap Ents $ mapM makeEnt ls


-- | Creates 'Ents'. Unlike 'ents' this function never fails because
-- you are restricted in the inputs that you can give it. It will
-- always infer the last Entry. All Entries except one will have the
-- same DrCr; the last, inferred one will have the opposite DrCr.
rEnts
  :: B.Commodity
  -- ^ Commodity for all postings
  -> B.DrCr
  -- ^ DrCr for all non-inferred postings
  -> (Either B.QtyRep B.Qty, m)
  -- ^ Non-inferred posting 1
  -> [(Either B.QtyRep B.Qty, m)]
  -- ^ Remaining non-inferred postings
  -> m
  -- ^ Metadata for inferred posting
  -> Ents m
rEnts com dc (q1, m1) nonInfs lastMeta =
  let tot = foldl' B.add (either B.toQty id q1)
            . map (either B.toQty id . fst) $ nonInfs
      p1 = makePstg (q1, m1)
      ps = map makePstg nonInfs
      makeEntry = either (\q -> Left (B.Entry dc (B.Amount q com)))
                         (\q -> Right (B.Entry dc (B.Amount q com)))
      makePstg (q, m) = Ent (makeEntry q) m False
      lastPstg = Ent (Right (B.Entry (B.opposite dc)
                                     (B.Amount tot com))) lastMeta True
  in Ents $ p1:ps ++ [lastPstg]


