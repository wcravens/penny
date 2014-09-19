module Penny.Copper.Commodity where

import qualified Penny.Copper.Caret as Caret
import qualified Penny.Copper.Commodity.Char as CharC
import Data.Sequence (Seq)

data T = T Caret.T (Seq CharC.T) Caret.T
  deriving (Eq, Ord, Show)
