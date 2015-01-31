module Penny.Copper.Ast where

import Control.Applicative
import Text.ParserCombinators.UU.BasicInstances hiding (Parser)
import Text.ParserCombinators.UU.Core
import Penny.Copper.Classes
import Penny.Lincoln.Rep
import Penny.Lincoln.Rep.Digits
import Penny.Copper.Intervals
import Penny.Lincoln.Side
import Penny.Lincoln.PluMin

data Located a = Located LineColPosA a
  deriving (Eq, Ord, Show)

pLocated :: Parser a -> Parser (Located a)
pLocated p = Located <$> pPos <*> p

-- | Something that might be followed by spaces.
data Fs a = Fs a (Maybe Whites)
  deriving (Eq, Ord, Show)

pFs :: Parser a -> Parser (Fs a)
pFs p = Fs <$> p <*> optional pWhites

-- | Something that might be preceded by spaces.
data Bs a = Bs (Maybe Whites) a
  deriving (Eq, Ord, Show)

pBs :: Parser a -> Parser (Bs a)
pBs p = Bs <$> optional pWhites <*> p

instance Functor Located where
  fmap f (Located l1 a) = Located l1 (f a)

rangeToParser :: Intervals Char -> Parser Char
rangeToParser i = case intervalsToTuples i of
  [] -> error "rangeToParser: empty interval"
  xs -> foldl1 (<|>) . map pRange $ xs

commentChar :: Intervals Char
commentChar = included [range minBound maxBound]
  `remove` alone '\n'

-- | Octothorpe
data Hash = Hash
  deriving (Eq, Ord, Show)

pHash :: Parser Hash
pHash = Hash <$ pSym '#'

data Newline = Newline
  deriving (Eq, Ord, Show)

pNewline :: Parser Newline
pNewline = Newline <$ pSym '\n'

newtype CommentChar = CommentChar Char
  deriving (Eq, Ord, Show)

pCommentChar :: Parser CommentChar
pCommentChar = CommentChar <$> rangeToParser commentChar

data Comment = Comment Hash [CommentChar] Newline
  deriving (Eq, Ord, Show)

pComment :: Parser Comment
pComment
  = Comment
  <$> pHash
  <*> many pCommentChar
  <*> pNewline

instance Parseable a => Parseable (Located a) where
  parser = Located <$> pPos <*> parser

data DigitsFour = DigitsFour Decem Decem Decem Decem
  deriving (Eq, Ord, Show)

pDigitsFour :: Parser DigitsFour
pDigitsFour = DigitsFour <$> pDecem <*> pDecem <*> pDecem <*> pDecem

data Digits1or2 = Digits1or2 Decem (Maybe Decem)
  deriving (Eq, Ord, Show)

pDigits1or2 :: Parser Digits1or2
pDigits1or2 = Digits1or2 <$> pDecem <*> optional pDecem

data DateSep = DateSlash | DateHyphen
  deriving (Eq, Ord, Show)

data DateA = DateA
  DigitsFour DateSep Digits1or2 DateSep Digits1or2
  deriving (Eq, Ord, Show)

pDateSep :: Parser DateSep
pDateSep = DateSlash <$ pSym '/' <|> DateHyphen <$ pSym '-'

pDateA :: Parser DateA
pDateA = DateA <$> pDigitsFour <*> pDateSep
               <*> pDigits1or2 <*> pDateSep <*> pDigits1or2

data Colon = Colon
  deriving (Eq, Ord, Show)

pColon :: Parser Colon
pColon = Colon <$ pSym ':'

data TimeA = TimeA
  Digits1or2 Colon Digits1or2 (Maybe (Colon, Digits1or2))
  deriving (Eq, Ord, Show)

instance Parseable TimeA where
  parser = TimeA <$> pDigits1or2 <*> pColon <*> pDigits1or2
    <*> optional ((,) <$> pColon <*> pDigits1or2)

data ZoneA = ZoneA Backtick PluMin DigitsFour
  deriving (Eq, Ord, Show)

instance Parseable ZoneA where
  parser = ZoneA <$> pBacktick <*> pPluMin <*> pDigitsFour

stringChar :: Intervals Char
stringChar = Intervals [range minBound maxBound]
  . map singleton $ bads
  where
    bads = ['\\', '\n', '"']

data DoubleQuote = DoubleQuote
  deriving (Eq, Ord, Show)

pDoubleQuote :: Parser DoubleQuote
pDoubleQuote = DoubleQuote <$ pSym '"'

newtype NonEscapedChar = NonEscapedChar Char
  deriving (Eq, Ord, Show)

pNonEscapedChar :: Parser NonEscapedChar
pNonEscapedChar = NonEscapedChar <$> rangeToParser stringChar

data Backslash = Backslash
  deriving (Eq, Ord, Show)

pBackslash :: Parser Backslash
pBackslash = Backslash <$ pSym '\\'

data White
  = Space
  | Tab
  | WhiteNewline
  | WhiteComment Comment
  deriving (Eq, Ord, Show)

pWhite :: Parser White
pWhite = Space <$ pSym ' ' <|> Tab <$ pSym '\t'
  <|> WhiteNewline <$ pSym '\n'
  <|> WhiteComment <$> pComment

data Whites = Whites White [White]
  deriving (Eq, Ord, Show)

pWhites :: Parser Whites
pWhites = Whites <$> pWhite <*> many pWhite

data EscPayload
  = EscBackslash
  | EscNewline
  | EscQuote
  | EscGap Whites Backslash
  deriving (Eq, Ord, Show)

pEscPayload :: Parser EscPayload
pEscPayload = EscBackslash <$ pSym '\\'
  <|> EscNewline <$ pSym '\n'
  <|> EscQuote <$ pSym '"'
  <|> EscGap <$> pWhites <*> pBackslash

data EscSeq = EscSeq Backslash EscPayload
  deriving (Eq, Ord, Show)

pEscSeq :: Parser EscSeq
pEscSeq = EscSeq <$> pBackslash <*> pEscPayload

newtype QuotedChar = QuotedChar (Either NonEscapedChar EscSeq)
  deriving (Eq, Ord, Show)

pQuotedChar :: Parser QuotedChar
pQuotedChar = QuotedChar <$>
  ( Left <$> pNonEscapedChar <|> Right <$> pEscSeq)

data QuotedString = QuotedString DoubleQuote [QuotedChar] DoubleQuote
  deriving (Eq, Ord, Show)

pQuotedString :: Parser QuotedString
pQuotedString = QuotedString
  <$> pDoubleQuote
  <*> many pQuotedChar
  <*> pDoubleQuote

newtype UnquotedStringChar = UnquotedStringChar Char
  deriving (Eq, Ord, Show)

unquotedStringChar :: Intervals Char
unquotedStringChar
  = Intervals [range minBound maxBound]
  . map singleton
  $ [ ' ', '\\', '\n', '\t', '{', '}', '[', ']', '\'', '"',
      '#', '@', '`']

pUnquotedStringChar :: Parser UnquotedStringChar
pUnquotedStringChar = UnquotedStringChar
  <$> rangeToParser unquotedStringChar

data UnquotedString
  = UnquotedString UnquotedStringChar [UnquotedStringChar]
  deriving (Eq, Ord, Show)

pUnquotedString :: Parser UnquotedString
pUnquotedString = UnquotedString
  <$> pUnquotedStringChar <*> many pUnquotedStringChar

-- | Pick between a list of parsers.  Each parser in the list gets
-- progressively more expensive.
choice :: [Parser a] -> Parser a
choice ps = foldr (<|>) empty . zipWith micro ps $ [1..]

-- Parsing the Trio
--
-- Whitespace is a space, tab, newline, or comment.
--
-- The Debit or Credit, if there is one, always comes first.  It is
-- followed by an optional run of whitespace.
--
-- If there is a Debit or Credit, the quantity must be Brim.
-- Otherwise, it must be Nil.
--
-- The commodity can be a quoted string, which is most flexible.  It
-- can also be a non-quoted string; in this case, it must not begin
-- with a digit (the other characters may be digits.)

newtype UnquotedCommodityFirstChar
  = UnquotedCommodityFirstChar Char
  deriving (Eq, Ord, Show)

unquotedCommodityFirstChar :: Intervals Char
unquotedCommodityFirstChar = unquotedStringChar `remove`
  included [range '0' '9']

pUnquotedCommodityFirstChar :: Parser UnquotedCommodityFirstChar
pUnquotedCommodityFirstChar = UnquotedCommodityFirstChar <$>
  rangeToParser unquotedCommodityFirstChar

data UnquotedCommodity
  = UnquotedCommodity UnquotedCommodityFirstChar [UnquotedStringChar]
  deriving (Eq, Ord, Show)

pUnquotedCommodity :: Parser UnquotedCommodity
pUnquotedCommodity = UnquotedCommodity
  <$> pUnquotedCommodityFirstChar <*> many pUnquotedStringChar

newtype QuotedCommodity = QuotedCommodity QuotedString
  deriving (Eq, Ord, Show)

pQuotedCommodity :: Parser QuotedCommodity
pQuotedCommodity = QuotedCommodity <$> pQuotedString

newtype CommodityA
  = CommodityA (Either UnquotedCommodity QuotedCommodity)
  deriving (Eq, Ord, Show)

pCommodityA :: Parser CommodityA
pCommodityA = CommodityA <$>
  (Left <$> pUnquotedCommodity <|> Right <$> pQuotedCommodity)

data Backtick = Backtick
  deriving (Eq, Ord, Show)

pBacktick :: Parser Backtick
pBacktick = Backtick <$ pSym '`'

data NonNeutral
  = NonNeutralRadCom Backtick (Brim RadCom)
  | NonNeutralRadPer (Brim RadPer)
  deriving (Eq, Ord, Show)

pNonNeutral :: Parser NonNeutral
pNonNeutral
  = NonNeutralRadCom <$> pBacktick <*> pBrim pRadixRadCom pRadCom
  <|> NonNeutralRadPer <$> pBrim pRadixRadPer pRadPer

data NeutralOrNon
  = NeutralOrNonRadCom Backtick (Either (Nil RadCom) (Brim RadCom))
  | NeutralOrNonRadPer (Either (Nil RadPer) (Brim RadPer))
  deriving (Eq, Ord, Show)

pNeutralOrNon :: Parser NeutralOrNon
pNeutralOrNon
  = NeutralOrNonRadCom <$> pBacktick <*>
      (Left <$> pNil pRadixRadCom pRadCom
        <|> Right <$> pBrim pRadixRadCom pRadCom)
  <|> NeutralOrNonRadPer <$>
      (Left <$> pNil pRadixRadPer pRadPer
        <|> Right <$> pBrim pRadixRadPer pRadPer)

-- | Trio.  There is nothing corresponding to 'Penny.Lincoln.Trio.E'
-- as this would screw up the spacing, and generally productions in
-- the AST should actually produce something.  Instead,
-- 'Penny.Lincoln.Trio.E' is indicated by the absense of any 'TrioA'.
data TrioA
  = QcCyOnLeftA (Fs Side) (Fs CommodityA) NonNeutral
  -- ^ Non neutral, commodity on left
  | QcCyOnRightA (Fs Side) (Fs NonNeutral) CommodityA
  -- ^ Non neutral, commodity on right
  | QA (Fs Side) NeutralOrNon
  -- ^ Qty with side only
  | SCA (Fs Side) CommodityA
  -- ^ Side and commodity
  | SA Side
  -- ^ Side only
  | UcCyOnLeftA (Fs CommodityA) NonNeutral
  -- ^ Unsigned quantity and commodity only, commodity on left
  | UcCyOnRightA (Fs NonNeutral) CommodityA
  -- ^ Unsigned quantity and commodity only, commodity on right
  | UA NonNeutral
  -- ^ Non-sided non-neutral quantity only
  | CA CommodityA
  -- ^ Commodity only
  deriving (Eq, Ord, Show)

pTrioA :: Parser TrioA
pTrioA = QcCyOnLeftA <$> pFs pSide <*> pFs pCommodityA <*> pNonNeutral
  <|> QcCyOnRightA <$> pFs pSide <*> pFs pNonNeutral <*> pCommodityA
  <|> QA <$> pFs pSide <*> pNeutralOrNon
  <|> SCA <$> pFs pSide <*> pCommodityA
  <|> SA <$> pSide
  <|> UcCyOnLeftA <$> pFs pCommodityA <*> pNonNeutral
  <|> UcCyOnRightA <$> pFs pNonNeutral <*> pCommodityA
  <|> UA <$> pNonNeutral
  <|> CA <$> pCommodityA

data OpenSquare = OpenSquare
  deriving (Eq, Ord, Show)

pOpenSquare :: Parser OpenSquare
pOpenSquare = OpenSquare <$ pSym '['

data CloseSquare = CloseSquare
  deriving (Eq, Ord, Show)

pCloseSquare :: Parser CloseSquare
pCloseSquare = CloseSquare <$ pSym ']'

data IntegerA = IntegerA (Maybe PluMin)
  (Either Zero (Novem, [Decem]))
  deriving (Eq, Ord, Show)

pIntegerA :: Parser IntegerA
pIntegerA = IntegerA <$> optional pPluMin <*>
  (Left <$> pZero <|> Right <$> ((,) <$> pNovem <*> many pDecem))

data ScalarA
  = ScalarUnquotedString UnquotedString
  | ScalarQuotedString QuotedString
  | ScalarDate DateA
  | ScalarTime TimeA
  | ScalarZone ZoneA
  | ScalarInt IntegerA
  deriving (Eq, Ord, Show)

pScalarA :: Parser ScalarA
pScalarA = choice
  [ ScalarDate <$> pDateA
  , ScalarTime <$> parser
  , ScalarZone <$> parser
  , ScalarInt <$> pIntegerA
  , ScalarQuotedString <$> pQuotedString
  , ScalarUnquotedString <$> pUnquotedString
  ]


data BracketedForest = BracketedForest
  (Fs OpenSquare) (Fs TreeA) CloseSquare
  deriving (Eq, Ord, Show)

pBracketedForest :: Parser BracketedForest
pBracketedForest = BracketedForest <$> pFs pOpenSquare
  <*> pFs pTreeA <*> pCloseSquare

data TreeA = TreeA (Located ScalarA) (Maybe (Bs BracketedForest))
  deriving (Eq, Ord, Show)

pTreeA :: Parser TreeA
pTreeA = TreeA <$> pLocated pScalarA <*> optional (pBs pBracketedForest)

data TopLineA = TopLineA TreeA [Bs TreeA]
  deriving (Eq, Ord, Show)

pTopLineA :: Parser TopLineA
pTopLineA = TopLineA <$> pTreeA <*> many (pBs pTreeA)

data PostingA
  = PostingTrioFirst (Located (Fs TrioA)) (Maybe BracketedForest)
  | PostingNoTrio BracketedForest
  deriving (Eq, Ord, Show)

pPostingA :: Parser PostingA
pPostingA
  = PostingTrioFirst <$> pLocated (pFs pTrioA)
                     <*> optional pBracketedForest
  <|> PostingNoTrio <$> pBracketedForest

data OpenCurly = OpenCurly
  deriving (Eq, Ord, Show)

pOpenCurly :: Parser OpenCurly
pOpenCurly = OpenCurly <$ pSym '{'

data CloseCurly = CloseCurly
  deriving (Eq, Ord, Show)

pCloseCurly :: Parser CloseCurly
pCloseCurly = CloseCurly <$ pSym '}'

data CommaA = CommaA
  deriving (Eq, Ord, Show)

pCommaA :: Parser CommaA
pCommaA = CommaA <$ pSym ','

data PostingsA = PostingsA (Fs OpenCurly)
  (Maybe (Fs PostingList)) CloseCurly
  deriving (Eq, Ord, Show)

pPostingsA :: Parser PostingsA
pPostingsA = PostingsA <$> pFs pOpenCurly
  <*> optional (pFs pPostingList) <*> pCloseCurly

data PostingList = PostingList (Located (Fs PostingA))
  [(CommaA, Bs (Located PostingA))]
  deriving (Eq, Ord, Show)

pPostingList :: Parser PostingList
pPostingList = PostingList <$> pLocated (pFs pPostingA)
  <*> many ((,) <$> pCommaA <*> pBs (pLocated pPostingA))

data TransactionA
  = TransactionWithTopLine (Located TopLineA)
      (Maybe (Bs PostingsA))
  | TransactionNoTopLine PostingsA
  deriving (Eq, Ord, Show)

pTransactionA :: Parser TransactionA
pTransactionA
  = TransactionWithTopLine <$> pLocated pTopLineA
      <*> optional (pBs pPostingsA)
  <|> TransactionNoTopLine <$> pPostingsA

data AtSign = AtSign
  deriving (Eq, Ord, Show)

pAtSign :: Parser AtSign
pAtSign = AtSign <$ pSym '@'

data PriceA = PriceA (Fs AtSign) (Located (Fs DateA))
  (Maybe (Located (Fs TimeA))) (Maybe (Located (Fs ZoneA)))
  (Fs CommodityA) ExchA
  deriving (Eq, Ord, Show)

pPriceA :: Parser PriceA
pPriceA = PriceA <$> pFs pAtSign <*> pLocated (pFs pDateA)
  <*> optional (pLocated (pFs parser))
  <*> optional (pLocated (pFs parser))
  <*> pFs pCommodityA <*> pExchA

data ExchA
  = ExchACy (Fs CommodityA) (Maybe (Fs PluMin)) NeutralOrNon
  | ExchAQty (Maybe (Fs PluMin)) (Fs NeutralOrNon) CommodityA
  deriving (Eq, Ord, Show)

pExchA :: Parser ExchA
pExchA = ExchACy <$> pFs pCommodityA <*> optional (pFs pPluMin)
               <*> pNeutralOrNon
  <|> ExchAQty <$> optional (pFs pPluMin) <*> pFs pNeutralOrNon
               <*> pCommodityA

data FileItem = FileItem (Located (Either PriceA TransactionA))
  deriving (Eq, Ord, Show)

pFileItem :: Parser FileItem
pFileItem = FileItem
  <$> pLocated ((Left <$> pPriceA) <|> (Right <$> pTransactionA))

data FileItems = FileItems FileItem [Bs FileItem]
  deriving (Eq, Ord, Show)

pFileItems :: Parser FileItems
pFileItems = FileItems <$> pFileItem <*> many (pBs pFileItem)

data File
  = FileNoLeadingWhite (Fs FileItems)
  | FileLeadingWhite Whites (Maybe (Fs FileItems))

pFile :: Parser File
pFile
  = FileNoLeadingWhite <$> pFs pFileItems
  <|> FileLeadingWhite <$> pWhites <*> (optional (pFs pFileItems))
