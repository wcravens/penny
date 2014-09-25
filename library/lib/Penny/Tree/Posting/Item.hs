module Penny.Tree.Posting.Item where

import qualified Penny.Tree.Flag as Flag
import qualified Penny.Tree.Number as Number
import qualified Penny.Tree.Payee.Posting as Payee
import qualified Penny.Tree.Account.Unquoted as Account.Unquoted
import qualified Penny.Tree.Account.Quoted as Account.Quoted
import qualified Penny.Tree.Tag as Tag
import qualified Penny.Tree.Side as Side

-- There is no need to import Currency; any Currency that is alone
-- will be parsed as an Ingot
import qualified Penny.Tree.Commodity as Commodity
import qualified Penny.Tree.Ingot as Ingot
import Control.Applicative
import Text.Parsec.Text

data T
  = T0 Flag.T
  | T1 Number.T
  | T2 Payee.T
  | T3 Account.Unquoted.T
  | T4 Account.Quoted.T
  | T5 Tag.T
  | T6 Side.T
  | T7 Commodity.T
  | T8 Ingot.T
  deriving (Eq, Ord, Show)

parser :: Parser T
parser
  = T0 <$> Flag.parser
  <|> T1 <$> Number.parser
  <|> T2 <$> Payee.parser
  <|> T3 <$> Account.Unquoted.parser
  <|> T4 <$> Account.Quoted.parser
  <|> T5 <$> Tag.parser
  <|> T6 <$> Side.parser
  <|> T7 <$> Commodity.parser
  <|> T8 <$> Ingot.parser
