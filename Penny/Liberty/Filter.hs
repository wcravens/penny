-- | A postings filter for use both by Zinc and by the Postings
-- report. Has all filtering aspects common to both these components. 

module Penny.Liberty.Filter where

import Control.Applicative ((<|>), (<$>))
import Control.Monad.Exception.Synchronous (Exceptional)
import Data.Monoid (mempty, mappend)
import Data.Text (Text)
import qualified Text.Matchers.Text as M
import System.Console.MultiArg.Prim (ParserE, feed, throw)

import Penny.Liberty.Error (Error)
import qualified Penny.Liberty.Error as E
import qualified Penny.Liberty.Expressions as X
import qualified Penny.Liberty.Matchers as PM
import qualified Penny.Liberty.Operands as O
import qualified Penny.Liberty.Operators as Oo
import qualified Penny.Liberty.PostFilters as PF
import qualified Penny.Liberty.Seq as PSq
import qualified Penny.Liberty.Sorter as S
import qualified Penny.Liberty.Types as T

import Penny.Copper.DateTime (DefaultTimeZone)
import Penny.Copper.Qty (Radix, Separator)
import Penny.Lincoln.Bits (DateTime)
import Penny.Lincoln.Boxes (PostingBox)

data State =
  State { sensitive :: M.CaseSensitive
        , factory :: Text -> Exceptional Text (Text -> Bool)
        , tokens :: [X.Token (T.PostingInfo -> Bool)]
        , postFilter :: [T.PostingInfo] -> [T.PostingInfo] }

newState :: State
newState =
  State { sensitive = M.Insensitive
        , factory = \t -> return (M.within M.Insensitive t)
        , tokens = []
        , postFilter = id }

wrapOperand ::
  DefaultTimeZone
  -> DateTime
  -> Radix
  -> Separator
  -> State
  -> ParserE Error State
wrapOperand dtz dt rad sep st =
  mkSt <$> O.parseToken dtz dt rad sep (factory st) where
    mkSt op = st { tokens = tokens st ++ [op'] } where
        op' = X.TokOperand (f . T.postingBox)
        (X.Operand f) = op

wrapOperator :: State -> ParserE Error State
wrapOperator st = mkSt <$> Oo.parser where
  mkSt f  = st { tokens = tokens st ++ [f] }

wrapMatcher :: State -> ParserE Error State
wrapMatcher st = mkSt <$> PM.parser cOld mOld where
  (cOld, mOld) = (sensitive st, factory st)
  mkSt (c, m) = st { sensitive = c, factory = m }
  
wrapSeq :: State -> ParserE Error State
wrapSeq st = mkSt <$> PSq.parser where
  mkSt op = st { tokens = tokens st ++ [op] }

wrapPostFilter :: State -> ParserE Error State
wrapPostFilter st = mkSt <$> PF.parser where
  mkSt fn = st { postFilter = fn . postFilter st }

parseOption ::
  DefaultTimeZone
  -> DateTime
  -> Radix
  -> Separator
  -> State
  -> ParserE Error State
parseOption dtz dt rad sp st =
  wrapOperand dtz dt rad sp st
  <|> wrapOperator st
  <|> wrapMatcher st
  <|> wrapSeq st
  <|> wrapPostFilter st

parseOptions ::
  DefaultTimeZone
  -> DateTime
  -> Radix
  -> Separator
  -> State
  -> ParserE Error State
parseOptions dtz dt rad sp = feed (parseOption dtz dt rad sp)
