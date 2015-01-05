module Penny.Lincoln.Prices.Internal where

import Penny.Lincoln.Commodity
import Data.Map (Map)
import qualified Data.Map as M
import Penny.Lincoln.Exch
import Penny.Lincoln.Qty
import Penny.Lincoln.DateTime
import Data.Time

newtype FromCy = FromCy Commodity
  deriving (Eq, Ord, Show)

newtype ToCy = ToCy Commodity
  deriving (Eq, Ord, Show)

data FromTo = FromTo
  { fromCy :: FromCy
  , toCy :: ToCy
  } deriving (Eq, Ord, Show)

fromTo :: FromCy -> ToCy -> Maybe FromTo
fromTo f@(FromCy fr) t@(ToCy to)
  | fr /= to = Just $ FromTo f t
  | otherwise = Nothing

convertQty
  :: Exch
  -> Qty
  -> Qty
convertQty (Exch exch) (Qty orig) = Qty $ exch * orig

newtype PriceDb = PriceDb
  (Map FromCy (Map ToCy (Map UTCTime Exch)))
  deriving (Eq, Ord, Show)

data Price = Price DateTime FromTo Exch
  deriving (Eq, Ord, Show)

emptyDb :: PriceDb
emptyDb = PriceDb M.empty

addPriceToDb :: PriceDb -> Price -> PriceDb
addPriceToDb (PriceDb db) (Price dt (FromTo fr to) exch)
  = PriceDb . M.alter fToMap fr $ db
  where
    utct = dateTimeToUTC dt
    fToMap mayToMap = case mayToMap of
      Nothing -> Just (M.singleton to (M.singleton utct exch))
      Just toMap -> Just $ M.alter fUTCmap to toMap
        where
          fUTCmap mayUTCmap = case mayUTCmap of
            Nothing -> Just $ M.singleton utct exch
            Just utcMap -> Just $ M.insert utct exch utcMap

data ExchLookupError
  = FromCommodityNotFound
  | ToCommodityNotFound
  | NoPreviousPrice
  deriving (Eq, Ord, Show)

lookupExch
  :: FromTo
  -> DateTime
  -> PriceDb
  -> Either ExchLookupError (UTCTime, Exch)
lookupExch (FromTo fr to) dt (PriceDb db) = do
  let utct = dateTimeToUTC dt
  toMap <- maybe (Left FromCommodityNotFound) Right
    . M.lookup fr $ db
  timeMap <- maybe (Left ToCommodityNotFound) Right
    . M.lookup to $ toMap
  maybe (Left NoPreviousPrice) Right
    . M.lookupLT utct $ timeMap