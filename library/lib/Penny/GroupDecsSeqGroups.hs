module Penny.GroupDecsSeqGroups where

import qualified Penny.Lincoln.Anna.DecDecs as DecDecs
import qualified Penny.SeqDecs as SeqDecs

data T r = T r DecDecs.T (SeqDecs.T r)
  deriving (Eq, Ord, Show)
