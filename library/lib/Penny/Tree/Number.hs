module Penny.Tree.Number where

import qualified Penny.Tree.Paren.Open as Open
import qualified Penny.Tree.Paren.Close as Close
import Data.Sequence (Seq)
import qualified Penny.Tree.Number.Char as Char
import Control.Applicative
import Text.Parsec.Text
import qualified Data.Sequence as S

data T = T Open.T (Seq Char.T) Close.T
  deriving (Eq, Ord, Show)

parser :: Parser T
parser
  = T
  <$> Open.parser
  <*> fmap S.fromList (many Char.parser)
  <*> Close.parser
