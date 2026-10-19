module Shoko.Adapter.Postgres.Query
  ( Identifier,
    identifier,
    Table (..),
    Scope (..),
    Predicate,
    equals,
    andAlso,
    SqlType (..),
    Query,
    ColumnResult (..),
    rowExists,
    rowAbsent,
    rowCount,
    columnValue,
    compileQuery,
    queryDescription,
    queryScope,
    queryDetails,
  )
where

import Data.Char (isAlphaNum, isAscii, isLetter)
import Data.Functor.Contravariant (contramap)
import Data.Int (Int64)
import Data.Text qualified as Text
import Hasql.Decoders qualified as D
import Hasql.Encoders qualified as E
import Hasql.Statement (Statement, unpreparable)
import Shoko.Correlation (Correlation (..))
import Shoko.Identifier
import Shoko.Observation (PublicValue (..))
import Shoko.Prelude

newtype Identifier = Identifier Text deriving stock (Eq, Show, Generic)

-- | A deliberately small identifier grammar. Quoting also preserves case.
identifier :: Text -> Either Text Identifier
identifier name
  | Text.length name <= 63,
    Just (first, _) <- Text.uncons name,
    isAscii first && (isLetter first || first == '_'),
    Text.all (\c -> isAscii c && (isAlphaNum c || c == '_')) name =
      Right (Identifier name)
  | otherwise = Left "invalid-sql-identifier"

data Table = Table !Identifier !Identifier deriving stock (Eq, Show, Generic)

data Scope = Scope !BusinessKeyName !Identifier deriving stock (Eq, Show, Generic)

data SqlType a where
  SqlText :: SqlType Text
  SqlInt64 :: SqlType Int64
  SqlBool :: SqlType Bool

data Predicate where
  Equal :: Identifier -> SqlType a -> a -> Predicate
  And :: Predicate -> Predicate -> Predicate

equals :: Identifier -> SqlType a -> a -> Predicate
equals = Equal

andAlso :: Predicate -> Predicate -> Predicate
andAlso = And

data ColumnResult a = NoRows | NullValue | OneValue !a | MultipleRows
  deriving stock (Eq, Show, Generic)

data Query a where
  Exists :: Table -> Scope -> Maybe Predicate -> Query Bool
  Absent :: Table -> Scope -> Maybe Predicate -> Query Bool
  Count :: Table -> Scope -> Maybe Predicate -> Query Int64
  Value :: Table -> Scope -> Maybe Predicate -> Identifier -> SqlType a -> Query (ColumnResult a)

rowExists :: Table -> Scope -> Maybe Predicate -> Query Bool
rowExists = Exists

rowAbsent :: Table -> Scope -> Maybe Predicate -> Query Bool
rowAbsent = Absent

rowCount :: Table -> Scope -> Maybe Predicate -> Query Int64
rowCount = Count

columnValue :: Table -> Scope -> Maybe Predicate -> Identifier -> SqlType a -> Query (ColumnResult a)
columnValue = Value

quote :: Identifier -> Text
quote (Identifier name) = "\"" <> name <> "\""

tableName :: Table -> Text
tableName (Table schema table) = quote schema <> "." <> quote table

encoder :: SqlType a -> E.Value a
encoder SqlText = E.text
encoder SqlInt64 = E.int8
encoder SqlBool = E.bool

decoder :: SqlType a -> D.Value a
decoder SqlText = D.text
decoder SqlInt64 = D.int8
decoder SqlBool = D.bool

renderPredicate :: Int -> Predicate -> (Text, E.Params (), Int)
renderPredicate index (Equal column kind value) =
  (quote column <> " = $" <> Text.pack (show index), contramap (const value) (E.param (E.nonNullable (encoder kind))), index + 1)
renderPredicate index (And left right) =
  let (l, le, next) = renderPredicate index left
      (r, re, end) = renderPredicate next right
   in ("(" <> l <> " AND " <> r <> ")", le <> re, end)

-- | Every query has a mandatory selected business-key predicate. There is no
-- unscoped or raw-fragment constructor. Values only enter binary parameters.
compileQuery :: Correlation -> Query a -> Either Text (Statement () a)
compileQuery selected query = case query of
  Exists table scope predicate -> statement table scope predicate (\whereSql -> "SELECT EXISTS (SELECT 1 FROM " <> tableName table <> whereSql <> ")") (D.singleRow (D.column (D.nonNullable D.bool)))
  Absent table scope predicate -> fmap not <$> compileQuery selected (Exists table scope predicate)
  Count table scope predicate -> statement table scope predicate (\whereSql -> "SELECT count(*) FROM " <> tableName table <> whereSql) (D.singleRow (D.column (D.nonNullable D.int8)))
  Value table scope predicate column kind -> statement table scope predicate (\whereSql -> "SELECT " <> quote column <> " FROM " <> tableName table <> whereSql <> " LIMIT 2") (classify <$> D.rowList (D.column (D.nullable (decoder kind))))
  where
    statement :: Table -> Scope -> Maybe Predicate -> (Text -> Text) -> D.Result b -> Either Text (Statement () b)
    statement _ (Scope key column) predicate sql result = case selected of
      ByBusinessKey selectedKey value
        | businessKeyNameText key /= "" && key == selectedKey && value /= "" ->
            let mandatory = Equal column SqlText value
                (whereSql, params, _) = renderPredicate 1 (maybe mandatory (And mandatory) predicate)
             in Right (unpreparable (sql (" WHERE " <> whereSql)) params result)
      _ -> Left "correlation-unavailable"
    classify [] = NoRows
    classify [Nothing] = NullValue
    classify [Just value] = OneValue value
    classify _ = MultipleRows

-- | The public shape excludes predicate and correlation values.
queryDescription :: Query a -> Text
queryDescription query = case query of
  Exists table _ _ -> "exists " <> tableName table <> " scoped"
  Absent table _ _ -> "absent " <> tableName table <> " scoped"
  Count table _ _ -> "count " <> tableName table <> " scoped"
  Value table _ _ column _ -> "value " <> tableName table <> "." <> quote column <> " scoped"

queryDetails :: Query a -> a -> [(Text, PublicValue)]
queryDetails (Exists _ _ _) value = [("exists", PublicFlag value)]
queryDetails (Absent _ _ _) value = [("absent", PublicFlag value)]
queryDetails (Count _ _ _) value = [("row-count", PublicCount (toInteger value))]
queryDetails (Value _ _ _ _ _) value = [("rows-seen", PublicCount (case value of NoRows -> 0; MultipleRows -> 2; _ -> 1))]

queryScope :: Query a -> Scope
queryScope (Exists _ scope _) = scope
queryScope (Absent _ scope _) = scope
queryScope (Count _ scope _) = scope
queryScope (Value _ scope _ _ _) = scope
