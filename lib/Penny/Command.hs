{-# LANGUAGE RankNTypes #-}

module Penny.Command where

import Penny.Amount
import Penny.Commodity
import Penny.Clatch
import Penny.Clatcher (Clatcher)
import qualified Penny.Clatcher as Clatcher
import Penny.Colors
import Penny.Columns (Colable, Columns)
import qualified Penny.Columns as Columns
import Penny.Converter
import Penny.Copper.Classes
import Penny.Copper.ConvertAst (c'DecUnsigned'NeutralOrNon)
import Penny.Decimal
import Penny.Natural
import Penny.Report
import Penny.Stream

import Control.Lens (set, Getter, view, to)
import qualified Data.Sequence as Seq
import Data.Text (Text, unpack)
import Text.Megaparsec (parseMaybe)


-- | Parses a value.  Applies 'error' if the value could not be parsed.
parse :: Parseable a => String -> Text -> a
parse msg txt = case parseMaybe parser txt of
  Nothing -> error $ "could not parse " ++ msg ++ " from input "
      ++ unpack txt
  Just r -> r

-- | Parses an unsigned decimal.  Applies 'error' if a value cannot be parsed.
unsigned :: Text -> DecUnsigned
unsigned = c'DecUnsigned'NeutralOrNon . parse "decimal value"

-- # Commands

convert
  :: Monoid r
  => Commodity
  -- ^ Convert from this commodity
  -> Commodity
  -- ^ Convert to this commodity
  -> Text
  -- ^ One unit of the from commodity equals this many of the to
  -- commodity.  Enter here a value that can be parsed into a zero or
  -- positive quantity.  If the value does not parse, 'error' will be
  -- applied with a short but slightly helpful error message.
  -> Clatcher r l
convert fromCy toCy factorTxt = set Clatcher.converter cv mempty
  where
    cv = Converter fn
    fn (Amount oldCy oldQty)
      | oldCy /= fromCy = Nothing
      | otherwise = Just $ Amount toCy (oldQty * factor)
    factor = fmap naturalToInteger . unsigned $ factorTxt

sieve
  :: Getter (Converted ()) Bool
  -> Clatcher r l
sieve f = set Clatcher.sieve (view f) mempty

sort :: (Prefilt () -> Prefilt () -> Ordering) -> Clatcher r l
sort f = set Clatcher.sort f mempty

screen
  :: Getter (Totaled ()) Bool
  -> Clatcher r l
screen f = set Clatcher.screen (view f) mempty


-- Output

output :: Stream -> Clatcher r l
output s = set Clatcher.output (Seq.singleton s) mempty

less :: Clatcher r l
less = output $ stream toLess

saveAs :: String -> Clatcher r l
saveAs = output . stream . toFile

colors :: Colors -> Clatcher r l
colors c = set Clatcher.colors c mempty

-- Report

report :: r -> Clatcher r l
report s = set Clatcher.report (Seq.singleton s) mempty

column :: Colable a => Getter Clatch a -> Clatcher Columns l
column f = set Clatcher.report (Seq.singleton $ Columns.column f) mempty

-- Load

preload :: String -> IO (Clatcher r Clatcher.LoadScroll)
preload = fmap make . Clatcher.preload
  where
    make scroll = set Clatcher.load (Seq.singleton scroll) mempty

open :: String -> Clatcher r Clatcher.LoadScroll
open str = set Clatcher.load (Seq.singleton (Clatcher.open str)) mempty

penny :: (Report r, Clatcher.Loader l) => Clatcher r l -> IO ()
penny = Clatcher.clatcher

-- Combinators

(&&&) :: Getter a Bool -> Getter a Bool -> Getter a Bool
l &&& r = to $ \a -> view l a && view r a
infixr 3 &&&

(|||) :: Getter a Bool -> Getter a Bool -> Getter a Bool
l ||| r = to $ \a -> view l a || view r a
infixr 2 |||
