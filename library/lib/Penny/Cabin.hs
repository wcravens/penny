module Penny.Cabin where

import qualified Penny.Janus as Janus
import qualified Penny.Zinc as Zinc

newtype T = T
  { toJanus :: Janus.T Zinc.T }


instance Eq T where
  (T x) == (T y) = Janus.isEqual (==) (==) x y

instance Ord T where
  compare (T a) (T b) = Janus.compare compare compare a b

instance Show T where
  show (T a) = Janus.show show show a
