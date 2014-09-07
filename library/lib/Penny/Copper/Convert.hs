-- | Modules in this hierarchy convert information from the trees in
-- the Penny.Copper.Tree hierarchy to types in the main Penny
-- hierarchy.
--
-- There are five steps to this process:
--
-- 1.  Locate.  Associates each line in each collection with its
-- associated line number.  Retains only posting memo lines,
-- transaction memo lines, transaction lines, and posting lines;
-- discards all other lines.
--
-- 2.  Serialize.  Associates posting lines with global and collection
-- serials, and top lines with global and collection serials.
--
-- Each of the following steps can fail.  If a step fails, keep the
-- failure message, but proceed to act upon as many more items as
-- possible.
--
-- 3.  Collect.  Gathers top lines with their memo lines and postings
-- with their memo lines, and the top lines with their associated
-- postings.
--
-- 4.  Transform.  Converts Penny.Copper.Tree top lines and postings to
-- mainline top lines and postings.
--
-- 5.  Validate.  Create balanced transactions.

module Penny.Copper.Convert where
