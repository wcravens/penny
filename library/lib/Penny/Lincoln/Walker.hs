module Penny.Lincoln.Walker where

import qualified Penny.Lincoln.Stokely as Lincoln
import qualified Penny.Lincoln.Side as Side

newtype T r
  = T { toLincoln :: Lincoln.T r Side.T }
  deriving (Eq, Ord, Show)
