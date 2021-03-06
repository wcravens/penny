{-# LANGUAGE OverloadedStrings #-}
module Penny.Brenner.Info (mode) where

import qualified Penny.Brenner.Types as Y
import qualified Data.Text as X
import qualified Data.Text.IO as TIO
import Data.Monoid ((<>))
import qualified Penny.Lincoln as L
import qualified Data.Sums as S
import qualified System.Console.MultiArg as MA

help :: String -> String
help pn = unlines
  [ "usage: " ++ pn ++ " info [options]"
  , "Shows further information about the configuration of your"
  , "financial institution accounts."
  , ""
  , "Options:"
  , "  -h, --help - show help and exit"
  ]

mode :: Y.Config -> MA.Mode (MA.ProgName -> String) (IO ())
mode cf = MA.modeHelp
  "info"               -- Mode name
  help                 -- Help function
  (const (process cf)) -- Processing function
  []                   -- Options
  MA.Intersperse       -- Interspersion
  processPa            -- Posarg processor
  where
    processPa = const . Left . MA.ErrorMsg
      $ "this mode does not accept positional arguments"

process :: Y.Config -> IO ()
process cf = TIO.putStr $ showInfo cf

showInfo :: Y.Config -> X.Text
showInfo cf =
  "These settings are compiled into your program.\n\n"
  <> showConfig cf

showConfig :: Y.Config -> X.Text
showConfig (Y.Config dflt more) =
  "Default financial institution account:"
  <> case dflt of
      Nothing -> " (no default)\n\n"
      Just d -> "\n\n" <> showFitAcct d <> "\n"
  <> "Additional financial institution accounts:"
  <> case more of
      [] -> " no additional accounts\n"
      ls -> "\n\n" <> showFitAccts ls

sepBar :: X.Text
sepBar = X.replicate 40 "=" <> "\n"

sepWithSpace :: X.Text
sepWithSpace = "\n" <> sepBar <> "\n"

showFitAccts :: [Y.FitAcct] -> X.Text
showFitAccts = X.intercalate sepWithSpace . map showFitAcct

label :: X.Text -> X.Text -> X.Text
label l t = l <> ": " <> t

showFitAcct :: Y.FitAcct -> X.Text
showFitAcct c =
  (L.text . Y.fitAcctName $ c) <> "\n\n"
  <> (L.text . Y.fitAcctDesc $ c) <> "\n"
  <> X.unlines
  [ label "Database location" (L.text . Y.dbLocation $ c)
  , label "Penny account" (L.text . L.Delimited ":" . Y.pennyAcct $ c)
  , label "Default account" (L.text . L.Delimited ":" . Y.defaultAcct $ c)
  , label "Currency" (L.text . Y.currency $ c)
  , label "Radix point and digit grouping"
    (showQtySpec . Y.qtySpec $ c)

  , label "Financial institution increases are"
    (showTranslator . Y.translator $ c)

  , label "In new postings, commodity is on the"
    (showSide . Y.side $ c)

  , label "Space between commodity and quantity in new postings"
    (showSpaceBetween . Y.spaceBetween $ c)
  ]
  <> "Parser description:\n"
  <> (L.text . fst . Y.parser $ c)

showQtySpec :: S.S3 L.Radix L.PeriodGrp L.CommaGrp -> X.Text
showQtySpec s = case s of
  S.S3a r -> "no digit grouping, use radix point: '"
             <> (L.showRadix r) <> "'"
  S.S3b p -> "group digits using: '"
             <> (X.singleton . L.groupChar $ p)
             <> "', radix point: '.'"
  S.S3c c -> "group digits using: '"
             <> (X.singleton . L.groupChar $ c)
             <> "', radix point: ','"


showTranslator :: Y.Translator -> X.Text
showTranslator y = case y of
  Y.IncreaseIsDebit -> "debits"
  Y.IncreaseIsCredit -> "credits"

showSide :: L.Side -> X.Text
showSide L.CommodityOnLeft = "left"
showSide L.CommodityOnRight = "right"

showSpaceBetween :: L.SpaceBetween -> X.Text
showSpaceBetween L.SpaceBetween = "yes"
showSpaceBetween L.NoSpaceBetween = "no"

{-
  label "Database location"
    (X.unpack . Y.unDbLocation . Y.dbLocation $ c)

  ++ label "Penny account"
     (showAccount . Y.unPennyAcct . Y.pennyAcct $ c)

  ++ label "Account for new offsetting postings"
     (showAccount . Y.unDefaultAcct . Y.defaultAcct $ c)

  ++ label "Currency"
     (X.unpack . L.unCommodity . Y.unCurrency . Y.currency $ c)

  ++ "\n"

  ++ "More information about the parser:\n"
  ++ (Y.unParserDesc . fst . Y.parser $ c)
  ++ "\n\n"


-}
