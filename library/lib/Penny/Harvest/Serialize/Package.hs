module Penny.Harvest.Serialize.Package where

import qualified Penny.Harvest.Serialize.Item as Item
import qualified Penny.Core.Clxn as Clxn
import qualified Penny.Harvest.Locate.Located as Located
import Data.Sequence (Seq)

data T = T
  { clxn :: Clxn.T
  , items :: Seq (Located.T Item.T)
  } deriving (Eq, Ord, Show)
