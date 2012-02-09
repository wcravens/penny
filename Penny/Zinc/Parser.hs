module Penny.Zinc.Parser where

import Control.Applicative ((<|>), (<$>))
import Data.Monoid (mempty)
import Data.Monoid.Extra (Orderer)
import System.Console.MultiArg.Prim (ParserE, feed)

import qualified Penny.Zinc.Parser.Filter as F
import qualified Penny.Zinc.Parser.Sorter as S
import Penny.Zinc.Parser.Error (Error)

import Penny.Copper.DateTime (DefaultTimeZone)
import Penny.Copper.Qty (Radix, Separator)
import Penny.Lincoln.Bits (DateTime)
import Penny.Lincoln.Boxes (PostingBox)

parseOption ::
  DefaultTimeZone
  -> DateTime
  -> Radix
  -> Separator
  -> (F.State t p, Orderer (PostingBox t p))
  -> ParserE Error (F.State t p, Orderer (PostingBox t p))
parseOption dtz dt rad sep (st, ord) =
  (\s -> (s, ord))    <$> F.parseToken dtz dt rad sep st
  <|> (\o -> (st, o)) <$> S.sort ord

parseOptions ::
  DefaultTimeZone
  -> DateTime
  -> Radix
  -> Separator
  -> (F.State t p, Orderer (PostingBox t p))
  -> ParserE Error (F.State t p, Orderer (PostingBox t p))
parseOptions dtz dt rad sep = feed (parseOption dtz dt rad sep)

defaultState :: (F.State t p, Orderer (PostingBox t p))
defaultState = (F.blankState, mempty)
