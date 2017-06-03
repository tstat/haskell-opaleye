> {-# LANGUAGE FlexibleContexts #-}
> {-# LANGUAGE DataKinds #-}
> module DefaultExplanation where
>
> import Opaleye (Column, Nullability(..), QueryRunner, Query,
>                 PGInt4, PGBool, PGText, PGFloat4)
> import qualified Opaleye as O
> import qualified Opaleye.Internal.Binary as Internal.Binary
> import Opaleye.Internal.Binary (Binaryspec)
>
> import Data.Profunctor.Product ((***!), p4)
> import Data.Profunctor.Product.Default (Default, def)
> import qualified Database.PostgreSQL.Simple as SQL

Introduction
============

Instances of `ProductProfunctor` are very common in Opaleye.  They are
first-class representations of various transformations that need to
occur in certain places.  The `Default` typeclass from
product-profunctors is used throughout Opaleye to avoid API users
having to write a lot of automatically derivable code, and it deserves
a thorough explanation.

Example
=======

By way of example we will consider the Binaryspec product-profunctor
and how it is used with the `unionAll` operation.  The version of
`unionAll` that does not have a Default constraint is called
`unionAllExplicit` and has the following type.

> unionAllExplicit :: Binaryspec a b -> Query a -> Query a -> Query b
> unionAllExplicit = O.unionAllExplicit

What is the `Binaryspec` used for here?  Let's take a simple case
where we want to union two queries of type `Query (Column NonNullable
PGInt4, Column NonNullable PGText)`

> myQuery1 :: Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
> myQuery1 = undefined -- We won't actually need specific implementations here
>
> myQuery2 :: Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
> myQuery2 = undefined

That means we will be using unionAll at the type

> unionAllExplicit' :: Binaryspec (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
>                                 (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
>                   -> Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
>                   -> Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
>                   -> Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
> unionAllExplicit' = unionAllExplicit

Since every `Column` is actually just a string containing an SQL
expression, `(Column 'NonNullable PGInt4, Column 'NonNullable PGText)`
is a pair of expressions.  When we generate the SQL we need to take
the two pairs of expressions, generate new unique names that refer to
them and produce these new unique names in another value of type
`(Column 'NonNullable PGInt4, Column 'NonNullable PGText)`.  This is
exactly what a value of type

    Binaryspec (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
               (Column 'NonNullable PGInt4, Column 'NonNullable PGText)

allows us to do.

So the next question is, how do we get our hands on a value of that
type?  Well, we have `binaryspecColumn` which is a value that allows
us to access the column name within a single column.

> binaryspecColumn :: Binaryspec (Column n a) (Column n a)
> binaryspecColumn = Internal.Binary.binaryspecColumn

`Binaryspec` is a `ProductProfunctor` so we can combine two of them to
work on a pair.

> binaryspecColumn2 :: Binaryspec (Column n a, Column m b) (Column n a, Column m b)
> binaryspecColumn2 = binaryspecColumn ***! binaryspecColumn

Then we can use `binaryspecColumn2` in `unionAllExplicit`.

> theUnionAll :: Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
> theUnionAll = unionAllExplicit binaryspecColumn2 myQuery1 myQuery2

Now suppose that we wanted to take a union of two queries with columns
in a tuple of size four.  We can make a suitable `Binaryspec` like
this:

> binaryspecColumn4 :: Binaryspec (Column j a, Column k b, Column m c, Column n d)
>                                 (Column j a, Column k b, Column m c, Column n d)
> binaryspecColumn4 = p4 (binaryspecColumn, binaryspecColumn,
>                         binaryspecColumn, binaryspecColumn)

Then we can pass this `Binaryspec` to `unionAllExplicit`.

The problem and 'Default' is the solution
=========================================

Constructing these `Binaryspec`s explicitly will become very tedious
very fast.  Furthermore it is completely pointless to construct them
explicitly because the correct `Binaryspec` can automatically be
deduced.  This is where the `Default` typeclass comes in.

`Opaleye.Internal.Binary` contains the `Default` instance

    instance Default Binaryspec (Column m a) (Column n a) where
      def = binaryspecColumn

That means that we know the "default" way of getting a

    Binaryspec (Column m a) (Column n a)

However, if we have a default way of getting one of these, we also
have a default way of getting a

    Binaryspec (Column m a, Column n b) (Column m a, Column n b)

just by using the `ProductProfunctor` product operation `(***!)`.  And
in the general case for a product type `T` with n type parameters we
can automatically deduce the correct value of type

    Binaryspec (T a1 ... an) (T a1 ... an)

(This requires the `Default` instance for `T` as generated by
`Data.Profunctor.Product.TH.makeAdaptorAndInstance`, or an equivalent
instance defined by hand).  It means we don't have to explicitly
specify the `Binaryspec` value.

Instead of writing `theUnionAll` as above, providing the `Binaryspec`
explicitly, we can instead use a version of `unionAll` which
automatically uses the default `Binaryspec` so we don't have to
provide it.  This is exactly what `Opaleye.Binary.unionAll` does.

> unionAll :: Default Binaryspec a b
>           => Query a -> Query a -> Query b
> unionAll = O.unionAllExplicit def
>
> theUnionAll' :: Query (Column 'NonNullable PGInt4, Column 'NonNullable PGText)
> theUnionAll' = unionAll myQuery1 myQuery2

In the long run this prevents writing a huge amount of boilerplate code.

A further example: `QueryRunner`
==============================

A `QueryRunner a b` is the product-profunctor which represents how to
turn run a `Query a` (currently on Postgres) and return you a list of
rows, each row of type `b`.  The function which is responsible for
this is `runQuery`

> runQueryExplicit :: QueryRunner a b -> SQL.Connection -> Query a -> IO [b]
> runQueryExplicit = O.runQueryExplicit

Basic values of `QueryRunner` will have the following types

> intRunner :: QueryRunner (Column 'NonNullable PGInt4) Int
> intRunner = undefined -- The implementation is not important here
>
> doubleRunner :: QueryRunner (Column 'NonNullable PGFloat4) Double
> doubleRunner = undefined
>
> stringRunner :: QueryRunner (Column 'NonNullable PGText) String
> stringRunner = undefined
>
> boolRunner :: QueryRunner (Column 'NonNullable PGBool) Bool
> boolRunner = undefined

Furthermore we will have basic ways of running queries which return
`Nullable` values, for example

> nullableIntRunner :: QueryRunner (Column 'Nullable PGInt4) (Maybe Int)
> nullableIntRunner = undefined

If I have a very simple query with a single column of `PGInt4` then I can
run it using the `intRunner`.

> myQuery3 :: Query (Column 'NonNullable PGInt4)
> myQuery3 = undefined -- The implementation is not important
>
> runTheQuery :: SQL.Connection -> IO [Int]
> runTheQuery c = runQueryExplicit intRunner c myQuery3

If my query has several columns of different types I need to build up
a larger `QueryRunner`.

> myQuery4 :: Query ( Column 'NonNullable PGInt4, Column 'NonNullable PGText
>                   , Column 'NonNullable PGBool, Column 'Nullable PGInt4
>                   )
> myQuery4 = undefined
>
> largerQueryRunner :: QueryRunner
>       (Column 'NonNullable PGInt4, Column 'NonNullable PGText, Column 'NonNullable PGBool, Column 'Nullable PGInt4)
>       (Int, String, Bool, Maybe Int)
> largerQueryRunner = p4 (intRunner, stringRunner, boolRunner, nullableIntRunner)
>
> runTheBiggerQuery :: SQL.Connection -> IO [(Int, String, Bool, Maybe Int)]
> runTheBiggerQuery c = runQueryExplicit largerQueryRunner c myQuery4

But having to build up `largerQueryRunner` was a pain and completely
redundant!  Like the `Binaryspec` it can be automatically deduced.
`Karamaan.Opaleye.RunQuery` already gives us `Default` instances for
the following types (plus many others, of course!).

* `QueryRunner (Column 'NonNullable PGInt4) Int`
* `QueryRunner (Column 'NonNullable PGText) String`
* `QueryRunner (Column 'NonNullable Bool) Bool`
* `QueryRunner (Column 'Nullable Int) (Maybe Int)`

Then the `Default` typeclass machinery automatically deduces the
correct value of the type we want.

> largerQueryRunner' :: QueryRunner
>       (Column 'NonNullable PGInt4, Column 'NonNullable PGText, Column 'NonNullable PGBool, Column 'Nullable PGInt4)
>       (Int, String, Bool, Maybe Int)
> largerQueryRunner' = def

And we can produce a version of `runQuery` which allows us to write
our query without explicitly passing the product-profunctor value.

> runQuery :: Default QueryRunner a b => SQL.Connection -> Query a -> IO [b]
> runQuery = O.runQueryExplicit def
>
> runTheBiggerQuery' :: SQL.Connection -> IO [(Int, String, Bool, Maybe Int)]
> runTheBiggerQuery' c = runQuery c myQuery4

Conclusion
==========

Much of the functionality of Opaleye depends on product-profunctors
and many of the values of the product-profunctors are automatically
derivable from some base collection.  The `Default` typeclass and its
associated instance derivations are the mechanism through which this
happens.
