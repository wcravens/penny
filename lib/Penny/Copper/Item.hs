module Penny.Copper.Item (
  itemWithLineNumber,
  Item(Transaction, Price, CommentItem, BlankLine),
  Line(unLine),
  render
  ) where

import Control.Applicative ((<$>), (<*>), (<$))
import qualified Data.Text as X
import Text.Parsec (getPosition, sourceLine, (<|>),
                    (<?>))
import Text.Parsec.Text ( Parser )

import qualified Penny.Copper.Comments as C
import qualified Penny.Copper.DateTime as DT
import qualified Penny.Lincoln as L
import qualified Penny.Copper.Qty as Q
import Penny.Copper.Price ( price )
import qualified Penny.Copper.Price as P
import qualified Penny.Copper.Transaction as T
import Penny.Copper.Transaction ( transaction )
import Penny.Copper.Util (eol)


-- | An Item is used both to hold the result of parsing an item from a
-- file and for rendering. It is parameterized on two types: the
-- metadata type for the TopLine, and the metadata type for the
-- Posting.
data Item tm pm = Transaction (L.Transaction tm pm)
                | Price (L.PricePoint L.PriceMeta)
                | CommentItem C.Comment
                | BlankLine
          deriving Show

newtype Line = Line { unLine :: Int }
               deriving (Eq, Show)

itemWithLineNumber ::
  DT.DefaultTimeZone
  -> Q.RadGroup
  -> Parser (Line, (Item (L.TopMemoLine, L.TopLineLine)
                    (L.PostingLine, Maybe L.Format)))
itemWithLineNumber dtz rg = (,)
  <$> ((Line . sourceLine) <$> getPosition)
  <*> parseItem dtz rg

parseItem ::
  DT.DefaultTimeZone
  -> Q.RadGroup
  -> Parser (Item (L.TopMemoLine, L.TopLineLine)
                    (L.PostingLine, Maybe L.Format))
parseItem dtz rg = let
   bl = BlankLine <$ eol <?> "blank line"
   t = Transaction <$> transaction dtz rg
   p = Price <$> price dtz rg
   c = CommentItem <$> C.comment
   in (bl <|> t <|> p <|> c)

render ::
  DT.DefaultTimeZone
  -> (Q.GroupingSpec, Q.GroupingSpec)
  -> Q.RadGroup
  -> Item () (Maybe L.Format)
  -> Maybe X.Text
render dtz gs rg i = case i of
  Transaction t -> T.render dtz gs rg t
  Price pp -> P.render dtz gs rg pp
  CommentItem c -> C.render c
  BlankLine -> Just $ X.singleton '\n'
    
