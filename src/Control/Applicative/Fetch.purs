-- | More efficient data fetching using deduplication, batching, and caching.
module Control.Applicative.Fetch
  ( Fetch
  , fetch
  , fetchAla
  , runFetch

  , class Resource
  , resource

  , Memoize(..)
  ) where

import Control.Monad.State.Class (class MonadState)
import Control.Monad.State.Class as State
import Data.Foldable (foldr)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (fromJust)
import Data.Newtype (class Newtype, unwrap)
import Data.Profunctor (class Profunctor)
import Data.Set (Set)
import Data.Set as Set
import Partial.Unsafe (unsafePartial)
import Prelude

--------------------------------------------------------------------------------

-- | A computation that fetches data for some set of keys. Fetch computations
-- | can be combined using `(<$>)` and `(<*>)`.
data Fetch k r a =
  Fetch (Set k) (Map k r -> a)

derive instance functorFetch :: Functor (Fetch k r)

instance applyFetch :: (Ord k) => Apply (Fetch k r) where
  apply (Fetch fks ff) (Fetch xks xf) =
    Fetch (Set.union fks xks) (ff <*> xf)

instance applicativeFetch :: (Ord k) => Applicative (Fetch k r) where
  pure = Fetch Set.empty <<< const

instance profunctorFetch :: Profunctor (Fetch k) where
  dimap l r (Fetch ks f) = Fetch ks (r <<< f <<< map l)

-- | A computation that fetches data for some key.
fetch :: ∀ k r. Ord k => k -> Fetch k r r
fetch k = Fetch (Set.singleton k) (unsafePartial fromJust <<< Map.lookup k)

-- | A computation that fetches data for some key, using some wrapping
-- | resource.
fetchAla :: ∀ k r r'. Ord k => Newtype r r' => (r' -> r) -> k -> Fetch k r r'
fetchAla _ = map unwrap <<< fetch

-- | Perform a fetch computation with some resource in some context.
runFetch :: ∀ k r f a. Resource k r f => Functor f => Fetch k r a -> f a
runFetch (Fetch ks f) = f <$> resource ks

--------------------------------------------------------------------------------

-- | A resource implements the fetching of data.
-- |
-- | Instances must satisfy the following laws in addition to the `Ord` laws:
-- |
-- | - Key preservation: `(true <$ resource ks) = map (\m -> all (Map.member <@> m) ks) (resource ks)`
class Ord k <= Resource k r f | k r -> f where
  resource :: Set k -> f (Map k r)

--------------------------------------------------------------------------------

-- | Cache fetched data indefinitely.
newtype Memoize r = Memoize r

derive instance newtypeMemoize :: Newtype (Memoize r) _

instance resourceMemoize :: (MonadState (Map k r) f, Resource k r f) =>
  Resource k (Memoize r) f where
  resource ks = do
    m <- State.get
    let ks' = foldr Set.delete ks (Map.keys m)
    r <- Map.union <@> m <$> resource ks'
    State.put r
    pure $ map Memoize r
