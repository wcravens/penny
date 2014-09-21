module Penny.Core.Philly where

import qualified Penny.Core.Janus as Janus
import qualified Penny.Core.Anna.Brim as Brim

data T = T
  { toJanus :: Janus.T Brim.T }

instance Eq T where
  (T x) == (T y) = Janus.isEqual (==) (==) x y

instance Ord T where
  compare (T a) (T b) = Janus.compare compare compare a b

instance Show T where
  show (T a) = Janus.show show show a
