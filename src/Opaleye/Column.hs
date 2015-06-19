module Opaleye.Column (module Opaleye.Column,
                       Column,
                       Nullable,
                       unsafeCoerce,
                       unsafeCast)  where

import           Opaleye.Internal.Column (Column, Nullable, unsafeCoerce, unsafeCast)
import qualified Opaleye.Internal.Column as C
import qualified Opaleye.Internal.HaskellDB.PrimQuery as HPQ
import qualified Opaleye.PGTypes as T
import           Prelude hiding (null)

-- | A NULL of any type
null :: Column (Nullable a)
null = C.Column (HPQ.ConstExpr HPQ.NullLit)

isNull :: Column (Nullable a) -> Column T.PGBool
isNull = C.unOp HPQ.OpIsNull

-- | If the @Column (Nullable a)@ is NULL then return the @Column b@
-- otherwise map the underlying @Column a@ using the provided
-- function.
--
-- The Opaleye equivalent of the 'Data.Maybe.maybe' function.
matchNullable :: Column b -> (Column a -> Column b) -> Column (Nullable a)
              -> Column b
matchNullable replacement f x = C.unsafeIfThenElse (isNull x) replacement
                                                   (f (unsafeCoerce x))

-- | If the @Column (Nullable a)@ is NULL then return the provided
-- @Column a@ otherwise return the underlying @Column a@.
--
-- The Opaleye equivalent of the 'Data.Maybe.fromMaybe' function
fromNullable :: Column a -> Column (Nullable a) -> Column a
fromNullable = flip matchNullable id

-- | The Opaleye equivalent of 'Data.Maybe.Just'
toNullable :: Column a -> Column (Nullable a)
toNullable = unsafeCoerce

-- | If the argument is 'Data.Maybe.Nothing' return NULL otherwise return the
-- provided value coerced to a nullable type.
maybeToNullable :: Maybe (Column a) -> Column (Nullable a)
maybeToNullable = maybe null toNullable
