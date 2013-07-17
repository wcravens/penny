{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE TemplateHaskell, GeneralizedNewtypeDeriving #-}

module Lincoln where

import Control.Applicative ((<$>), (<*>))
import Control.Monad (liftM2, liftM5, liftM4, liftM3, replicateM, guard)
import Data.List (foldl1')
import Data.Maybe (isJust, isNothing, catMaybes)
import Data.Monoid (mempty)
import qualified Data.Time as T
import qualified Test.QuickCheck as Q
import qualified Test.QuickCheck.Gen as QG
import qualified Test.QuickCheck.Property as QCP
import qualified Test.QuickCheck.All as A
import Test.QuickCheck (Gen, Arbitrary, arbitrary, (==>))
import qualified Penny.Lincoln as L
import Penny.Lincoln.Equivalent ((==~))
import Data.Text (Text)
import qualified Data.Text as X
import System.Random.Shuffle (shuffle')

--
-- # Qty
--

failMsg :: Monad m => String -> m a
failMsg s = fail $ s ++ ": generation failed"

-- | Generates Qty with the exponent restricted to a reasonable
-- size. Currently this means it is between 0 and 5, inclusive. Big
-- mantissas are not a problem, but big exponents quickly make the
-- tests practically un-runnable.
genReasonableExp :: Gen L.Qty
genReasonableExp = do
  m <- Q.suchThat Q.arbitrarySizedBoundedIntegral (> (0 :: Int))
  p <- Q.choose (0 :: Int, 5)
  maybe (failMsg "genSmallSized") return
    $ L.newQty (fromIntegral m) (fromIntegral p)

maxExponent :: Integer
maxExponent = 5

genExponent :: Gen Integer
genExponent = Q.choose (0, maxExponent)

-- | Mutates a Qty so that it is equivalent, but possibly with a
-- different mantissa and exponent.
genEquivalent :: L.Qty -> Gen L.Qty
genEquivalent q = do
  let (m, p) = (L.mantissa q, L.places q)
  expo <- genExponent
  let m' = m * (10 ^ expo)
      p' = p + (fromIntegral expo)
  maybe (failMsg "genEquivalent") return $ L.newQty m' p'

-- | Mutates a Qty so that it is not equivalent. Changes either the
-- mantissa or the exponent or both.
genMutate :: L.Qty -> Gen L.Qty
genMutate q = do
  let (m, p) = (L.mantissa q, L.places q)
  (changeMantissa, changeExp) <-
    Q.suchThat (liftM2 (,) arbitrary arbitrary)
    (/= (False, False))
  m' <- if changeMantissa then mutateAtLeast1 m else return m
  p' <- if changeExp then mutateExponent p else return p
  maybe (failMsg "genMutate") return $ L.newQty m' p'

-- | genMutate generates non-equivalent quantities
prop_genMutate :: L.Qty -> Gen Bool
prop_genMutate q = fmap f $ genMutate q
  where
    f q' = not $ q ==~ q'

-- | genEquivalent generates equivalent quantities
prop_genEquivalent :: L.Qty -> Gen Bool
prop_genEquivalent q = fmap f $ genEquivalent q
  where
    f q' = q ==~ q'

-- | Mutates an Integer.  The result is always at least one.
mutateAtLeast1 :: Integer -> Gen Integer
mutateAtLeast1 i =
  fmap fromIntegral $ Q.suchThat Q.arbitrarySizedBoundedIntegral pdct
  where
    pdct = if i > (fromIntegral (maxBound :: Int))
              || i < (fromIntegral (minBound :: Int))
           then (>= (1 :: Int))
           else (\r -> r >= 1 && r /= (fromIntegral i))

-- | Mutates an Integer. The result is always at least zero.
mutateExponent :: Integer -> Gen Integer
mutateExponent i = Q.suchThat (Q.choose (0, maxExponent)) (/= i)

-- | Generates one, with different exponents.
genOne :: Gen L.Qty
genOne = do
  p <- Q.choose (0, maxExponent)
  maybe (failMsg "genOne") return $ L.newQty (1 * 10 ^ p) p

-- | Chooses one of 'genSized' or 'genRangeInt' or 'genSmallExp'.
instance Arbitrary L.Qty where
  arbitrary = Q.oneof [ genReasonableExp ]

-- | Mantissas are always greater than zero.
prop_mantissa :: L.Qty -> Bool
prop_mantissa q = L.mantissa q > 0

-- | Exponent is always at least zero
prop_exponent :: L.Qty -> Bool
prop_exponent q = L.places q >= 0

-- | newQty passes if exponent is at least zero and if mantissa is
-- greater than zero.

prop_newQtySucceeds :: L.Mantissa -> L.Places -> Q.Property
prop_newQtySucceeds m p =
  m > 0 ==> p >= 0 ==> isJust (L.newQty m p)

-- | True if this is a valid Qty; that is, the mantissa is greater
-- than 0 and the number of places is greater than or equal to 0.
validQty :: L.Qty -> Bool
validQty q = L.mantissa q > 0 && L.places q >= 0


maxSizeList :: Arbitrary a => Int -> Gen [a]
maxSizeList i = Q.sized $ \s -> do
  len <- Q.choose (0, min s i)
  Q.vector len

-- | Generates a group of balanced quantities.
genBalQtys :: Gen (L.Qty, [L.Qty], [L.Qty])
genBalQtys = maxSize 5 $ do
  total <- arbitrary
  group1alloc1 <- arbitrary
  group1allocRest <- arbitrary
  group2alloc1 <- arbitrary
  group2allocRest <- arbitrary
  let (g1r1, g1rs) = L.allocate total (group1alloc1, group1allocRest)
      (g2r1, g2rs) = L.allocate total (group2alloc1, group2allocRest)
  return $ (total, g1r1 : g1rs, g2r1 : g2rs)

-- | genBalQtys generates first qty list that sum up to the given total.
prop_genBalQtysTotalX :: Q.Property
prop_genBalQtysTotalX = Q.forAll genBalQtys $ \(tot, g1, _) ->
  let sx = foldl1 L.add g1
  in if sx ==~ tot
     then QCP.succeeded
     else let r = "planned sum: " ++ show tot ++ " actual sum: "
                  ++ show sx
          in QCP.failed { QCP.reason = r }

-- | genBalQtys generates a balanced group of quantities.
prop_genBalQtys :: Q.Property
prop_genBalQtys = Q.forAll genBalQtys $ \(tot, g1, g2) ->
  case (g1, g2) of
    (x:xs, y:ys) ->
      let sx = foldl1' L.add (x:xs)
          sy = foldl1' L.add (y:ys)
      in if sx ==~ sy
         then QCP.succeeded
         else let r = "Different sums. X sum: " ++ show sx
                      ++ " Y sum: " ++ show sy ++
                      " planned total: " ++ show tot
              in QCP.failed { QCP.reason = r }
    _ -> QCP.failed { QCP.reason = "empty quantities list" }

-- | > x + y == y + x

prop_commutative :: L.Qty -> L.Qty -> Bool
prop_commutative q1 q2 = q1 `L.add` q2 == q2 `L.add` q1

-- | Adding q2 to q1 and then taking the difference of q2 gives a
-- LeftBiggerBy q1

prop_addSubtract :: L.Qty -> L.Qty -> Bool
prop_addSubtract q1 q2 =
  let diff = (q1 `L.add` q2) `L.difference` q2
  in case diff of
      L.LeftBiggerBy d -> d ==~ q1
      _ -> False

-- | add generates valid Qtys
prop_addValid :: L.Qty -> L.Qty -> Bool
prop_addValid q1 q2 = validQty $ q1 `L.add` q2

-- | mult generates valid Qtys
prop_multValid :: L.Qty -> L.Qty -> Bool
prop_multValid q1 q2 = validQty $ q1 `L.mult` q2

newtype One = One { unOne :: L.Qty }
  deriving (Eq, Show)

instance Arbitrary One where arbitrary = fmap One genOne

-- | genOne generates valid Qtys
prop_genOneValid :: One -> Bool
prop_genOneValid = validQty . unOne

-- | (x `mult` 1) `equivalent` x
prop_multIdentity :: L.Qty -> One -> Bool
prop_multIdentity x (One q1) = (x `L.mult` q1) ==~ x

-- | newQty fails if mantissa is less than one
prop_newQtyBadMantissa :: L.Mantissa -> L.Places -> Q.Property
prop_newQtyBadMantissa m p =
  m < 1 ==> isNothing (L.newQty m p)

-- | newQty fails if places is less than zero
prop_newQtyBadPlaces :: L.Mantissa -> L.Places -> Q.Property
prop_newQtyBadPlaces m p =
  m < 0 ==> isNothing (L.newQty m p)

-- | difference returns valid L.Qty
prop_differenceValid :: L.Qty -> L.Qty -> Bool
prop_differenceValid q1 q2 = case L.difference q1 q2 of
  L.LeftBiggerBy r -> validQty r
  L.RightBiggerBy r -> validQty r
  L.Equal -> True

-- | allocate returns valid Qty
prop_allocateValid :: L.Qty -> (L.Qty, [L.Qty]) -> Bool
prop_allocateValid q1 q2 =
  let (r1, r2) = L.allocate q1 q2
  in validQty r1 && all validQty r2

-- | 'equivalent' fails on different Qty
prop_genNotEquivalent :: L.Qty -> Gen Bool
prop_genNotEquivalent q1 = do
  q2 <- genMutate q1
  return . not $ q1 ==~ q2

-- | newQty succeeds and fails as it should, and generates valid Qty
prop_newQty :: L.Mantissa -> L.Places -> Bool
prop_newQty m p = case (m > 0, p >= 0) of
  (True, True) -> case L.newQty m p of
    Nothing -> False
    Just q -> L.mantissa q == m && L.places q == p
  _ -> isNothing (L.newQty m p)

-- | Sum of allocation adds up to original Qty

prop_sumAllocate :: L.Qty -> (L.Qty, [L.Qty]) -> Bool
prop_sumAllocate tot ls =
  let (r1, rs) = L.allocate tot ls
  in foldl1' L.add (r1:rs) ==~ tot

-- | Number of allocations is same as number requested

prop_numAllocate :: L.Qty -> (L.Qty, [L.Qty]) -> Bool
prop_numAllocate tot ls =
  let (_, rs) = L.allocate tot ls
  in length rs == length (snd ls)

-- | Sum of largest remainder method is equal to total number of seats
prop_sumLargestRemainder
  :: Q.Positive Integer
  -> Q.NonEmptyList (Q.NonNegative Integer)
  -> QCP.Property

prop_sumLargestRemainder tot ls =
  let t = Q.getPositive tot
      l = map Q.getNonNegative . Q.getNonEmpty $ ls
      r = L.largestRemainderMethod t l
  in sum l > 0 ==> sum r == t

--
-- # DateTime
--

instance Arbitrary L.TimeZoneOffset where
  arbitrary = Q.choose (-840, 840)
    >>= maybe (failMsg "timeZoneOffset") return . L.minsToOffset

instance Arbitrary L.Hours where
  arbitrary = Q.choose (0, 23)
    >>= maybe (failMsg "hours") return . L.intToHours

instance Arbitrary L.Minutes where
  arbitrary = Q.choose (0, 59)
    >>= maybe (failMsg "minutes") return . L.intToMinutes

instance Arbitrary L.Seconds where
  arbitrary = Q.choose (0, 60)
    >>= maybe (failMsg "seconds") return . L.intToSeconds

genDay :: Q.Gen T.Day
genDay = fmap T.ModifiedJulianDay $ Q.choose (b, e)
  where
    b = T.toModifiedJulianDay $ T.fromGregorian 1000 01 01
    e = T.toModifiedJulianDay $ T.fromGregorian 3000 01 01

instance Arbitrary L.DateTime where
  arbitrary = liftM5 L.DateTime genDay
    arbitrary arbitrary arbitrary arbitrary

--
-- # Open
--

maxSize :: Int -> Gen a -> Gen a
maxSize i g = Q.sized $ \s -> Q.resize (min i s) g

-- | Generates a Text from valid Unicode chars.
genText :: Gen Text
genText = maxSize 5
  $ fmap X.pack $ Q.oneof [ Q.listOf ascii, Q.listOf rest ]
  where
    ascii = Q.choose (toEnum 32, toEnum 126)
    rest = Q.suchThat (Q.choose (minBound, maxBound))
                       (\c -> c < '\xd800' || c > '\xdfff')

instance Arbitrary L.SubAccount where
  arbitrary = fmap L.SubAccount genText

instance Arbitrary L.Account where
  arbitrary = fmap L.Account arbitrary

instance Arbitrary L.Amount where
  arbitrary = liftM2 L.Amount arbitrary arbitrary

instance Arbitrary L.Commodity where
  arbitrary = fmap L.Commodity genText

instance Arbitrary L.DrCr where
  arbitrary = Q.elements [L.Debit, L.Credit]

instance Arbitrary L.Entry where
  arbitrary = liftM2 L.Entry arbitrary arbitrary

instance Arbitrary L.Flag where
  arbitrary = fmap L.Flag genText

instance Arbitrary L.Memo where
  arbitrary = fmap L.Memo $ Q.listOf genText

instance Arbitrary L.Number where
  arbitrary = fmap L.Number genText

instance Arbitrary L.Payee where
  arbitrary = fmap L.Payee genText

instance Arbitrary L.Tag where
  arbitrary = fmap L.Tag genText

instance Arbitrary L.Tags where
  arbitrary = fmap L.Tags $ Q.listOf arbitrary

instance Arbitrary L.TopLineLine where
  arbitrary = fmap L.TopLineLine Q.arbitrarySizedBoundedIntegral

instance Arbitrary L.TopMemoLine where
  arbitrary = fmap L.TopMemoLine Q.arbitrarySizedBoundedIntegral

instance Arbitrary L.Side where
  arbitrary = Q.elements [L.CommodityOnLeft, L.CommodityOnRight]

instance Arbitrary L.SpaceBetween where
  arbitrary = Q.elements [L.SpaceBetween, L.NoSpaceBetween]

instance Arbitrary L.Filename where
  arbitrary = fmap L.Filename genText

instance Arbitrary L.PriceLine where
  arbitrary = fmap L.PriceLine Q.arbitrarySizedBoundedIntegral

instance Arbitrary L.PostingLine where
  arbitrary = fmap L.PostingLine Q.arbitrarySizedBoundedIntegral

instance Arbitrary L.GlobalPosting where
  arbitrary = fmap L.GlobalPosting arbitrary

instance Arbitrary L.FilePosting where
  arbitrary = fmap L.FilePosting arbitrary

instance Arbitrary L.GlobalTransaction where
  arbitrary = fmap L.GlobalTransaction arbitrary

instance Arbitrary L.FileTransaction where
  arbitrary = fmap L.FileTransaction arbitrary

instance Arbitrary L.Serial where
  arbitrary = do
    ls <- Q.listOf1 (return ())
    let sers = L.serialItems const ls
    fmap head $ shuffle sers

-- | Shuffles a list.
shuffle :: [a] -> Gen [a]
shuffle ls = QG.MkGen $ \g _ ->
  shuffle' ls (length ls) g

--
-- # Ents
--

-- | Generates restricted ents
genRestricted :: Arbitrary a => Gen (L.Ents a)
genRestricted = liftM5 L.rEnts arbitrary arbitrary arbitrary
                arbitrary arbitrary

-- | Generates a group of balanced entries.
genBalEntries :: Gen ([L.Entry])
genBalEntries = do
  (_, qDeb, qCred) <- genBalQtys
  let qtysAndDrCrs = map (\en -> (L.Debit, en)) qDeb
                     ++ map (\en -> (L.Credit, en)) qCred
  cty <- arbitrary
  let mkEn (drCr, qty) = L.Entry drCr (L.Amount qty cty)
  shuffle $ map mkEn qtysAndDrCrs

newtype BalEntries = BalEntries
  { unBalEntries :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary BalEntries where
  arbitrary = fmap BalEntries genBalEntries

-- | Generates a list of entries. At most, one of these is Inferred.
genEntriesWithInfer :: Gen [(L.Entry, L.Inferred)]
genEntriesWithInfer = do
  nGroups <- Q.suchThat Q.arbitrarySizedIntegral (> 0)
  entries <- fmap concat $ replicateM nGroups genBalEntries
  makeNothing <- arbitrary
  let entries' = if makeNothing
        then (head entries, L.Inferred)
             : map (\en -> (en, L.NotInferred)) (tail entries)
        else map (\en -> (en, L.NotInferred)) entries
  shuffle entries'


-- | Gets a single inferred entry from a balance, if possible.
inferredVal :: [Maybe L.Entry] -> Maybe L.Entry
inferredVal ls = do
  guard ((length . filter id . map isNothing $ ls) == 1)
  case L.entriesToBalanced . catMaybes $ ls of
    L.Inferable e -> Just e
    _ -> Nothing

-- | genEntriesWithInfer is inferable
prop_genEntries :: Q.Property
prop_genEntries = Q.forAll genEntriesWithInfer $
  \ps -> L.Inferred `elem` (map snd ps)
         ==> isJust (inferredVal (map toEn ps))
  where
    toEn (en, inf) = if inf == L.Inferred then Nothing else Just en

-- | genBalEntries generates groups that are balanced.
prop_balEntries :: BalEntries -> Bool
prop_balEntries
  = (== L.Balanced)
  . L.entriesToBalanced
  . unBalEntries

-- | 'views' gives as many views as there were postings

prop_numViews :: L.Ents m -> Bool
prop_numViews t = (length . L.views $ t) == (length . L.unEnts $ t)

newtype NonRestricted a = NonRestricted
  { unNonRestricted :: [(Maybe L.Entry, a)] }
  deriving (Eq, Show)

instance Arbitrary a => Arbitrary (NonRestricted a) where
  arbitrary = do
    ls <- genEntriesWithInfer
    metas <- Q.vector (length ls)
    let mkPair (en, inf) mt = case inf of
          L.Inferred -> (Nothing, mt)
          L.NotInferred -> (Just en, mt)
    return . NonRestricted $ zipWith mkPair ls metas

genNonRestricted :: Arbitrary a => Gen (L.Ents a)
genNonRestricted =
  arbitrary
  >>= maybe (failMsg "genNonRestricted") return
      . L.ents
      . unNonRestricted

instance Arbitrary a => Arbitrary (L.Ents a) where
  arbitrary = Q.oneof [ genNonRestricted
                       , genRestricted ]

-- | Ents always have at least two postings
prop_twoPostings :: L.Ents a -> Bool
prop_twoPostings e = length (L.unEnts e) > 1

-- | Ents are always balanced
prop_balanced :: L.Ents a -> Bool
prop_balanced
  = (== L.Balanced)
  . L.entriesToBalanced
  . map L.entry
  . L.unEnts

-- | Ents contain no more than one inferred posting
prop_inferred :: L.Ents a -> Bool
prop_inferred t =
  (length . filter (== L.Inferred) . map L.inferred . L.unEnts $ t)
  < 2

newtype BalQtys = BalQtys { _unBalQtys :: ([L.Qty], [L.Qty]) }
  deriving (Eq, Show)

-- | 'ents' makes ents as it should. Also tests whether
-- the 'Arbitrary' instance of 'NonRestricted' is behaving as it
-- should.

prop_ents :: NonRestricted a -> Bool
prop_ents (NonRestricted ls) = isJust $ L.ents ls

-- | NonRestricted makes ents with two postings
prop_entsTwoPostings :: NonRestricted a -> Bool
prop_entsTwoPostings (NonRestricted ls) = case L.ents ls of
  Nothing -> False
  Just t -> prop_twoPostings t

-- | 'rEnts' behaves as it should

prop_rEnts
  :: L.Commodity
  -> L.DrCr
  -> (L.Qty, a)
  -> [(L.Qty, a)]
  -> a
  -> Bool
prop_rEnts c dc pr ls mt =
  let t = L.rEnts c dc pr ls mt
  in prop_twoPostings t && prop_balanced t && prop_inferred t

-- Testing that 'ents' fails when it should

-- | Generates a group of entries that are not balanced or inferable
genNotInferable :: Arbitrary a => Gen [(Maybe L.Entry, a)]
genNotInferable = QG.suchThat gen notInf
  where
    notInf ls =
      let bal = L.entriesToBalanced
                . catMaybes
                . map fst
                $ ls
      in bal == L.NotInferable
    gen = QG.listOf $ (,) <$> arbitrary <*> arbitrary


newtype NotInferable a = NotInferable
  { unNotBalanced :: [(Maybe L.Entry, a)] }
  deriving (Eq, Show)

instance Arbitrary a => Arbitrary (NotInferable a) where
  arbitrary = NotInferable <$> genNotInferable

-- | 'ents' fails when given non-inferable entries
prop_entsNonInferable :: Arbitrary a => NotInferable a -> Bool
prop_entsNonInferable (NotInferable ls) =
  isNothing $ L.ents ls

--
-- # Price
--

instance Arbitrary L.From where
  arbitrary = fmap L.From arbitrary
instance Arbitrary L.To where
  arbitrary = fmap L.To arbitrary
instance Arbitrary L.CountPerUnit where
  arbitrary = fmap L.CountPerUnit arbitrary

instance Arbitrary L.Price where
  arbitrary = do
    (f, t) <- Q.suchThat arbitrary (\(f, t) -> L.unFrom f /= L.unTo t)
    c <- arbitrary
    maybe (failMsg "price") return $ L.newPrice f t c

-- | All Prices have from and to commodities that are different.
prop_price :: L.Price -> Bool
prop_price p = (L.unFrom . L.from $ p)
               /= (L.unTo . L.to $ p)

-- | newPrice succeeds if From and To are different
prop_newPriceDifferent :: L.CountPerUnit -> Q.Property
prop_newPriceDifferent cpu =
  Q.forAll (Q.suchThat arbitrary (\(L.From f, L.To t) -> f /= t)) $
  \(f, t) -> isJust (L.newPrice f t cpu)

-- | newPrice fails if From and To are the same
prop_newPriceSame :: L.From -> L.CountPerUnit -> Bool
prop_newPriceSame (L.From fr) cpu =
  isNothing (L.newPrice (L.From fr) (L.To fr) cpu)

--
-- # Bits
--
instance Arbitrary L.PricePoint where
  arbitrary = liftM5 L.PricePoint arbitrary arbitrary arbitrary
              arbitrary arbitrary

instance Arbitrary L.TopLineData where
  arbitrary = liftM3 L.TopLineData arbitrary arbitrary arbitrary

instance Arbitrary L.TopLineCore where
  arbitrary = liftM5 L.TopLineCore arbitrary arbitrary arbitrary
              arbitrary arbitrary

instance Arbitrary L.TopLineFileMeta where
  arbitrary = liftM4 L.TopLineFileMeta arbitrary arbitrary arbitrary
              arbitrary

instance Arbitrary L.PostingCore where
  arbitrary = L.PostingCore <$> arbitrary <*> arbitrary <*> arbitrary
              <*> arbitrary <*> arbitrary <*> arbitrary <*> arbitrary
              <*> arbitrary

instance Arbitrary L.PostingFileMeta where
  arbitrary = liftM2 L.PostingFileMeta arbitrary arbitrary

instance Arbitrary L.PostingData where
  arbitrary = liftM3 L.PostingData arbitrary arbitrary arbitrary

--
-- # Balance
--

-- | The Balanced of an empty Balance is always Balanced.
prop_emptyBalance :: Bool
prop_emptyBalance = L.balanced mempty == L.Balanced

-- | The Balanced of a list of Entry where all the commodities are the
-- same is always Balanced or Inferable.
prop_entriesSameCommodity
  :: [(L.Qty, L.DrCr)]
  -- ^ The Qty and DrCr of each Entry

  -> L.Commodity
  -- ^ Single Commodity for all Entry

  -> Bool

prop_entriesSameCommodity ls cy =
  let mkEntry (qt, dc) = L.Entry dc (L.Amount qt cy)
      entries = map mkEntry ls
  in case L.entriesToBalanced entries of
      L.Balanced -> True
      L.Inferable _ -> True
      _ -> False

-- | Two Commodities that are not the same.
newtype CommodityPair = CommodityPair
  { unCommodityPair :: (L.Commodity, L.Commodity) }
  deriving (Eq, Show)

instance Arbitrary CommodityPair where
  arbitrary =
    CommodityPair <$> QG.suchThat gen (\(c1, c2) -> c1 /= c2)
    where
      gen = (,) <$> arbitrary <*> arbitrary

-- | The Balanced where there is at least one Entry of one commodity
-- and exactly one Entry of another commodity is either Inferable or
-- NotInferable.

prop_entriesTwoCommodities
  :: Q.NonEmptyList (L.Qty, L.DrCr)
  -- ^ Qty and DrCr of the group of Entry that has at least one Entry

  -> (L.Qty, L.DrCr)
  -- ^ Qty and DrCr of the group that has exactly one Entry

  -> CommodityPair

  -> Bool

prop_entriesTwoCommodities (Q.NonEmpty qd1) qd2 cp =
  let mkEntry cy (q, dc) = L.Entry dc (L.Amount q cy)
      g1 = map (mkEntry (fst . unCommodityPair $ cp)) qd1
      g2 = mkEntry (snd . unCommodityPair $ cp) qd2
      balanced = L.entriesToBalanced $ g2:g1
  in case balanced of
      L.Balanced -> False
      _ -> True


-- | Mutates a Commodity.
mutateCommodity :: L.Commodity -> Gen L.Commodity
mutateCommodity (L.Commodity cy) =
  L.Commodity <$> QG.suchThat genText (\c -> c /= cy)



-- | mutateCommodity behaves as it should
prop_mutateCommodity :: L.Commodity -> Gen Bool
prop_mutateCommodity c = do
  c' <- mutateCommodity c
  return $ c /= c'

-- | Mutating the commodity of a balanced group of entries results in
-- an NotInferable balance.
newtype NotInferableFromBalanced = NotInferableFromBalanced
  { unNotInferableFromBalanced :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary NotInferableFromBalanced where
  arbitrary = do
    BalEntries ls <- arbitrary
    let en = head ls
    cy' <- mutateCommodity . L.commodity . L.amount $ en
    let en' = L.Entry (L.drCr en) (L.Amount (L.qty . L.amount $ en)
                                            cy')
    fmap NotInferableFromBalanced . shuffle $ en' : tail ls


-- | NotInferableFromBalanced behaves as it should
prop_notInferableFromBalanced :: NotInferableFromBalanced -> Bool
prop_notInferableFromBalanced
  = (== L.NotInferable)
  . L.entriesToBalanced
  . unNotInferableFromBalanced

-- | Mutating the DrCr of a Balanced group yields an Inferable.
newtype InferableMutatedDrCr = InferableMutatedDrCr
  { unInferableMutatedDrCr :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary InferableMutatedDrCr where
  arbitrary = do
    BalEntries ls <- arbitrary
    let en = head ls
        dc' = L.opposite . L.drCr $ en
        en' = L.Entry dc' (L.amount en)
    fmap InferableMutatedDrCr . shuffle $ en' : tail ls

-- | InferableMutatedDrCr behaves as it should
prop_inferableMutatedDrCr :: InferableMutatedDrCr -> Bool
prop_inferableMutatedDrCr
  = L.isInferable
  . L.entriesToBalanced
  . unInferableMutatedDrCr

-- | Mutating the Qty of a Balanced group yields an Inferable.
newtype InferableMutatedQty = InferableMutatedQty
  { unInferableMutatedQty :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary InferableMutatedQty where
  arbitrary = do
    BalEntries ls <- arbitrary
    let en = head ls
        am = L.amount en
        cy = L.commodity am
    q <- genMutate . L.qty $ am
    let en' = L.Entry (L.drCr en) (L.Amount q cy)
    fmap InferableMutatedQty . shuffle $ en' : tail ls

-- | InferableMutatedQty behaves as it should
prop_inferableMutatedQty :: InferableMutatedQty -> Bool
prop_inferableMutatedQty
  = L.isInferable
  . L.entriesToBalanced
  . unInferableMutatedQty

-- | A mix of InferableMutatedQty and InferableMutatedDrCr
newtype InferableGroup = InferableGroup
  { unInferableGroup :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary InferableGroup where
  arbitrary
    = InferableGroup
    <$> Q.oneof [ fmap unInferableMutatedDrCr arbitrary
                , fmap unInferableMutatedQty arbitrary ]

-- | NotInferable groups, generated at random
newtype NotInferableRandom = NotInferableRandom
  { unNotInferableRandom :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary NotInferableRandom where
  arbitrary = fmap NotInferableRandom $ Q.suchThat arbitrary pd
    where
      pd = (== L.NotInferable) . L.entriesToBalanced

-- | A mix of NotInferableFromBalanced and NotInferableRandom
newtype NotInferableGroup = NotInferableGroup
  { unNotInferableGroup :: [L.Entry] }
  deriving (Eq, Show)

instance Arbitrary NotInferableGroup where
  arbitrary = NotInferableGroup
    <$> Q.oneof [ fmap unNotInferableRandom arbitrary
                , fmap unNotInferableFromBalanced arbitrary ]

-- | Any number of BalEntries is Balanced
prop_balEntriesBalanced :: [BalEntries] -> Bool
prop_balEntriesBalanced
  = (== L.Balanced)
  . L.entriesToBalanced
  . concat
  . map unBalEntries

-- | Any number of BalEntries and one Inferable is Inferable
prop_balEntriesAndInferable :: [BalEntries] -> InferableGroup -> Bool
prop_balEntriesAndInferable bals inf
  = L.isInferable
  . L.entriesToBalanced
  . (++ unInferableGroup inf)
  . concat
  . map unBalEntries
  $ bals

-- | Any number of BalEntries and one NotInferable is not inferable
prop_balEntriesAndNotInferable
  :: [BalEntries] -> NotInferableGroup -> Bool
prop_balEntriesAndNotInferable bals notInf
  = (== L.NotInferable)
  . L.entriesToBalanced
  . (++ unNotInferableGroup notInf)
  . concat
  . map unBalEntries
  $ bals

--
-- # ents fails properly
--

pairWithInts :: [a] -> Gen [(a, Int)]
pairWithInts ls = fmap (zip ls) (Q.vector (length ls))

-- | 'ents' fails when given NonInferableGroup
prop_noEntsNotInferableGroup
  :: Q.NonEmptyList NotInferableGroup

  -> Maybe (Maybe L.Entry)
  -- ^ Optionally throws in another Maybe Entry; ents should fail
  -- regardless of whether another entry is present or not

  -> Gen Bool
prop_noEntsNotInferableGroup nib mayMayEnt = do
  let es = map Just . concat . map unNotInferableGroup
           . Q.getNonEmpty $ nib
      esWithExtra = maybe es (: es) mayMayEnt
  esWithInts <- pairWithInts esWithExtra
  return . isNothing . L.ents $ esWithInts

--
-- # runTests
--
runTests :: (Q.Property -> IO Q.Result) -> IO Bool
runTests = $(A.forAllProperties)
