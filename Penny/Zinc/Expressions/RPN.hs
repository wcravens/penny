module Penny.Zinc.Expressions.RPN (
  Operand(Operand),
  Operator(Unary, Binary),
  Token(TokOperand, TokOperator),
  process) where

import Penny.Zinc.Expressions.Stack (
  Stack, push, empty, View(Empty, (:->)),
  view)
import Penny.Zinc.Expressions.Queue (Front, View((:<)))
import qualified Penny.Zinc.Expressions.Queue as Q

newtype Operand a = Operand a deriving Show

data Operator a =
  Unary (a -> a)
  | Binary (a -> a -> a)

instance Show (Operator a) where
  show (Unary _) = "<unary operator>"
  show (Binary _) = "<binary operator>"

data Token a =
  TokOperand (Operand a)
  | TokOperator (Operator a)
  deriving Show

type RPN a = Front (Token a)

type Operands a = Stack (Operand a)

processOperator ::
  Operator a
  -> Operands a
  -> Maybe (Operands a)
processOperator t ds = case t of
  (Unary f) -> case view ds of
    Empty -> Nothing
    (Operand x) :-> xs -> return $ push (Operand (f x)) xs
  (Binary f) -> case view ds of
    Empty -> Nothing
    (Operand x) :-> dss -> case view dss of
      (Operand y) :-> dsss ->
        return $ push (Operand (f y x)) dsss
      Empty -> Nothing

processOperand ::
  Operand a
  -> Operands a
  -> Operands a
processOperand = push

processToken ::
  Token a
  -> Operands a
  -> Maybe (Operands a)
processToken tok s = case tok of
  TokOperand d -> return (processOperand d s)
  TokOperator t -> processOperator t s

process :: RPN a -> Maybe a
process i = case popTokens i of
  Just os -> case view os of
    (Operand x) :-> oss -> case view oss of 
      Empty -> Just x
      _ -> Nothing
    _ -> Nothing
  _ -> Nothing

popTokens :: RPN a
             -> Maybe (Operands a)
popTokens i = case popTokens' i empty of
  Nothing -> Nothing
  Just (is, s') -> case Q.view is of
    Q.Empty -> return s'
    _ -> Nothing

popTokens' :: RPN a
             -> Operands a
             -> Maybe (RPN a, Operands a)
popTokens' ts s = case Q.view ts of
  Q.Empty -> return (ts, s)
  x :< xs -> do
    s' <- processToken x s
    popTokens' xs s'

--
-- Testing
--

-- 19
{-
_input :: RPN Int
_input = RPN [ TokOperand (Operand 4)
             , TokOperand (Operand 5)
             , TokOperand (Operand 8)
             , TokOperator (Binary (*))
             , TokOperand (Operand 6)
             , TokOperator (Binary (-))
             , TokOperator (Binary (+))
             , TokOperand (Operand 2)
             , TokOperator (Binary div) ]
-}