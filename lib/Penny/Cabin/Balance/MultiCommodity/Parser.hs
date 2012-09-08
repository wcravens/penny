module Penny.Cabin.Balance.MultiCommodity.Parser (
  Error(..)
  , ParseOpts(..)
  , parseOptions
  ) where

import qualified Data.Text as X
import Control.Applicative ((<|>), many, Applicative, pure)
import Control.Monad ((>=>))
import qualified Control.Monad.Exception.Synchronous as Ex
import qualified Penny.Cabin.Colors as Col
import qualified Penny.Cabin.Colors.DarkBackground as DB
import qualified Penny.Cabin.Colors.LightBackground as LB
import qualified Penny.Cabin.Chunk as Chk
import qualified Penny.Cabin.Options as CO
import qualified Penny.Copper.Commodity as CC
import qualified Penny.Copper.DateTime as CD
import qualified Penny.Lincoln as L
import qualified Penny.Shield as S
import System.Console.MultiArg.Prim (Parser)
import qualified System.Console.MultiArg.Combinator as C
import qualified Text.Parsec as Parsec

-- | Options for the Balance report that have been parsed from the command line.
data ParseOpts = ParseOpts {
  drCrColors :: Col.DrCrColors
  , baseColors :: Col.BaseColors
  , colorPref :: Chk.Colors
  , showZeroBalances :: CO.ShowZeroBalances
  , convert :: Maybe (L.Commodity, L.DateTime)
  }


data Error = BadColorName String
           | BadBackground String
           | BadCommodity String
           | BadDate String
             deriving Show


processColorArg ::
  S.Runtime
  -> String
  -> Maybe Chk.Colors
processColorArg rt x
  | x == "yes" = return Chk.Colors8
  | x == "no" = return Chk.Colors0
  | x == "auto" = return (CO.maxCapableColors rt)
  | x == "256" = return Chk.Colors256
  | otherwise = Nothing

parseOpt :: [String] -> [Char] -> C.ArgSpec a -> Parser a
parseOpt ss cs a = C.parseOption [C.OptSpec ss cs a]

color :: Parser (S.Runtime
                 -> ParseOpts
                 -> Ex.Exceptional Error ParseOpts)
color = parseOpt ["color"] "" (C.OneArg f)
  where
    f a1 rt op = case processColorArg rt a1 of
      Nothing -> Ex.throw . BadColorName $ a1
      Just c -> return (op { colorPref = c })

processBackgroundArg ::
  String
  -> Maybe (Col.DrCrColors, Col.BaseColors)
processBackgroundArg x
  | x == "light" = return (LB.drCrColors, LB.baseColors)
  | x == "dark" = return (DB.drCrColors, DB.baseColors)
  | otherwise = Nothing


background :: Parser (ParseOpts -> Ex.Exceptional Error ParseOpts)
background = parseOpt ["background"] "" (C.OneArg f)
  where
    f a1 op = case processBackgroundArg a1 of
      Nothing -> Ex.throw . BadBackground $ a1
      Just (dc, base) ->
        return op { drCrColors = dc
                  , baseColors = base }

parseShowZeroBalances :: Parser (ParseOpts -> ParseOpts)
parseShowZeroBalances = parseOpt opt "" (C.NoArg f)
  where
    opt = ["show-zero-balances"] 
    f op =
      op {showZeroBalances = CO.ShowZeroBalances True }

hideZeroBalances :: Parser (ParseOpts -> ParseOpts)
hideZeroBalances = parseOpt ["hide-zero-balances"] "" (C.NoArg f)
  where
    f op =
      op {showZeroBalances = CO.ShowZeroBalances False }

convertLong ::
  Parser (CD.DefaultTimeZone
          -> ParseOpts
          -> Ex.Exceptional Error ParseOpts)
convertLong = parseOpt ["convert"] "" (C.TwoArg f)
  where
    f a1 a2 dtz op = do
      cty <- case Parsec.parse CC.lvl1Cmdty "" (X.pack a1) of
        Left _ -> Ex.throw . BadCommodity $ a1
        Right g -> return g
      let parseDate = CD.dateTime dtz
      dt <- case Parsec.parse parseDate "" (X.pack a2) of
        Left _ -> Ex.throw . BadDate $ a2
        Right g -> return g
      let op' = op { convert = Just (cty, dt) }
      return op'

convertShort :: Parser (S.Runtime
                        -> ParseOpts
                        -> Ex.Exceptional Error ParseOpts)
convertShort = parseOpt [] ['c'] (C.OneArg f)
  where
    f a1 rt op = do
      cty <- case Parsec.parse CC.lvl1Cmdty "" (X.pack a1) of
        Left _ -> Ex.throw . BadCommodity $ a1
        Right g -> return g
      let dt = S.currentTime rt
          op' = op { convert = Just (cty, dt) }
      return op'
        

-- | Parses all options for the Balance report from the command
-- line. Run this parser after parsing the name of the report
-- (e.g. @bal@ or @balance@) from the command line. This parser will
-- parse all words after the name of the report up to the the ledger
-- file names. The result is a computation, which can fail if the user
-- supplies a DateTime or a Commodity on the command line that fails
-- to parse or if the user supplies a argument for the @--background@
-- option that fails to parse.
parseOptions :: Parser (S.Runtime
                        -> CD.DefaultTimeZone
                        -> ParseOpts
                        -> Ex.Exceptional Error ParseOpts)
parseOptions = do
  fns <- many parseOption
  let f rt dtz o1 =
        let fns' = map (\fn -> fn rt dtz) fns
        in foldl (>=>) return fns' o1
  return f

parseOption :: Parser (S.Runtime
                       -> CD.DefaultTimeZone
                       -> ParseOpts
                       -> Ex.Exceptional Error ParseOpts)
parseOption =
  (do { f <- color; return (\rt _ o -> f rt o )})
  <|> wrap background
  <|> wrap (impurify parseShowZeroBalances)
  <|> wrap (impurify hideZeroBalances)
  <|> (do { f <- convertLong; return (\_ dtz o -> f dtz o )})
  <|> (do { f <- convertShort; return (\rt _ o -> f rt o )})
  where
    wrap p = do
      f <- p
      return (\_ _ op -> f op)

impurify ::
  (Applicative m, Functor f)
  => f (a -> a)
  -> f (a -> m a)
impurify = fmap (\f -> pure . f)
