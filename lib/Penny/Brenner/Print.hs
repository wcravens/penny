-- | Prints parsed transactions.
--
-- TODO add support to this and other Brenner components for reading
-- from stdin.
module Penny.Brenner.Print (mode) where

import qualified Penny.Brenner.Types as Y
import qualified Penny.Brenner.Util as U
import qualified System.Console.MultiArg as MA
import qualified System.IO as IO
import qualified System.Exit as E
import qualified Control.Monad.Exception.Synchronous as Ex
import Data.Maybe (mapMaybe)

help :: String
help = unlines
  [ "penny-fit [global-options] print [local-options] FILE..."
  , "Parses the transactions in each FILE using the appropriate parser"
  , "and prints the parse result to standard output."
  , ""
  , "Local options:"
  , "  --help, -h Show this help and exit."
  ]

data Arg
  = ArgHelp
  | ArgFile String
  deriving (Eq, Show)

mode
  :: Maybe Y.FitAcct
  -> MA.Mode (Ex.Exceptional String (IO ()))
mode mayFa = MA.Mode
  { MA.mName = "print"
  , MA.mIntersperse = MA.Intersperse
  , MA.mOpts = [MA.OptSpec ["help"] "h" (MA.NoArg ArgHelp)]
  , MA.mPosArgs = ArgFile
  , MA.mProcess = processor mayFa
  }

processor
  :: Maybe Y.FitAcct
  -> [Arg]
  -> Ex.Exceptional String (IO ())
processor mayFa ls =
  if any (== ArgHelp) ls
  then return (putStrLn help)
  else case mayFa of
          Nothing -> Ex.throw $
            "no financial institution account"
            ++ " provided on command line, and no account"
            ++ " configured by default."
          Just fa -> return $ doPrint (snd . Y.parser $ fa) ls

doPrint
  :: (Y.FitFileLocation -> IO (Ex.Exceptional String [Y.Posting]))
  -> [Arg]
  -> IO ()
doPrint prsr ls = mapM_ f . mapMaybe toFile $ ls
  where
    f file = do
      r <- prsr file
      case r of
        Ex.Exception s -> do
          IO.hPutStrLn IO.stderr $ "penny-fit print: error: " ++ s
          E.exitFailure
        Ex.Success ps -> mapM putStr . map U.showPosting $ ps
    toFile a = case a of
      ArgFile s -> Just (Y.FitFileLocation s)
      _ -> Nothing
