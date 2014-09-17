-- | Numbers - how numbers work in Penny
--
-- Representing numbers accurately is a considerable challenge in
-- Penny.  Wherever possible, Penny uses the type system to help meet
-- this challenge, so that the data types closely reflect the
-- constraints on data.  To the maximum extent possible, this means
-- that modules export all constructors and that the structure of the
-- types themselves represent constraints; I made types abstract only
-- as a last resort.  This simplifies testing and documentation, but
-- it does mean there are a huge number of types involved.
--
-- Numbers can roughly be divided into three categories:
-- representation, concrete, and parse trees.
--
-- Representation types use the type system to represent the presence
-- or absence of digit grouping characters, the type of the radix
-- point (comma or period), and whether the value is zero or non-zero.
-- Types in this classification include:
--
-- * "Penny.Cabin", contains either a zero value or a non-zero value
-- along with a "Penny.Side" polarity.
--
-- * "Penny.Philly", contains a non-zero value only.
--
-- * "Penny.Anna", contains either a zero value or a non-zero value,
-- with no polarity.
--
-- Concrete types contain values that, ultimately, are wrappers around
-- 'Deka.Dec.Dec' values.  Concrete types are the only ones that can
-- be used for arithmetic; however, the type is harder to use in case
-- statements because 'Deka.Dec.Dec' is not composed of smaller
-- compoent types.  Concrete types include:
--
-- * "Penny.Qty", contains a quantity
--
-- * "Penny.Exchange", contains an exchange, which is a number that
-- states the value of one commodity in terms of a different commodity
--
-- Parse tree types represent the results of parsing.  A parse tree
-- captures not only a representation but also an optional commodity.
-- Parse trees are rooted at "Penny.Wheat".

module Penny.Docs.Numbers where

{-

(* EBNF grammar for number parse trees.

Wheat
