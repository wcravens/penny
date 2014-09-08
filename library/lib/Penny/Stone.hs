module Penny.Stone where

import qualified Penny.Gravel as Gravel
import qualified Penny.PluMin as PluMin
import qualified Penny.Cement as Cement

newtype T = T { toGravel :: Gravel.T PluMin.T }
  deriving (Eq, Ord, Show)

fromGravel :: Gravel.T PluMin.T -> T
fromGravel = T

toCement :: T -> Cement.T
toCement = Gravel.toCement PluMin.toSign . toGravel

fromCement :: Cement.T -> T
fromCement = T . Gravel.fromCement PluMin.fromSign