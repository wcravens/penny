module Main where

import Control.Monad
import Data.Text ( pack )
import qualified Data.Text.IO as TIO
import Data.Time
import System.Environment
import Text.Parsec
import Text.PrettyPrint

import Penny.Copper
import Penny.Denver.Pretty

main :: IO ()
main = do
  dtz <- liftM DefaultTimeZone getCurrentTimeZone
  (a:[]) <- getArgs
  f <- TIO.readFile a
  let (rad, spr) = radixAndSeparator '.' ','
      fn = Filename (pack a)
      e = parse (ledger fn dtz rad spr) a f
  putStrLn (render . pretty $ e)
