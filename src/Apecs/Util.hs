{-# LANGUAGE Strict, ScopedTypeVariables, TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts, FlexibleInstances #-}

module Apecs.Util
  ( runGC, initStore,
    EntityCounter, initCounter, nextEntity, newEntity,
    ConcatQueries(..),
    quantize, flatten, region, inbounds
  ) where

import System.Mem (performMajorGC)
import Control.Monad.Reader (liftIO)
import Control.Applicative (liftA2)

import Apecs.Core
import Apecs.Stores


newtype EntityCounter = EntityCounter Int
instance Component EntityCounter where
  type Storage EntityCounter = Global EntityCounter

initCounter :: IO (Storage EntityCounter)
initCounter = initStoreWith (EntityCounter 0)

{-# INLINE nextEntity #-}
nextEntity :: Has w EntityCounter => System w (Entity ())
nextEntity = do EntityCounter n <- readGlobal
                writeGlobal (EntityCounter (n+1))
                return (Entity n)

{-# INLINE newEntity #-}
newEntity :: (IsRuntime c, Has w c, Has w EntityCounter)
          => c -> System w (Entity c)
newEntity c = do ety <- nextEntity
                 set (cast ety) c
                 return (cast ety)

runGC :: System w ()
runGC = liftIO performMajorGC

initStore :: (Initializable s, InitArgs s ~ ()) => IO s
initStore = initStoreWith ()

newtype ConcatQueries q = ConcatQueries [q]
instance Query q s => Query (ConcatQueries q) s where
  explSlice s (ConcatQueries qs) = mconcat <$> traverse (explSlice s) qs

-- | The following functions are for spatial hashing.
--   The idea is that your spatial hash is defined by two vectors;
--     - The cell size vector contains real components and dictates
--       how large each cell in your table is spatially.
--       It is used to translate from world-space to table space
--     - The field size vector contains integral components and dictates how
--       many cells your field consists of in each direction.
--       It is used to translate from table-space to a flat integer

-- | Quantize turns a world-space coordinate into a table-space coordinate by dividing
--   by the given cell size and round components towards negative infinity
{-# INLINE quantize #-}
quantize :: (Fractional (v a), Integral b, RealFrac a, Functor v)
         => v a -- ^ Quantization cell size
         -> v a -- ^ Vector to be quantized
         -> v b
quantize cell vec = floor <$> vec/cell

-- | For two table-space vectors indicating a region's bounds, gives a list of the vectors contained between them.
--   This is useful for querying a spatial hash.
{-# INLINE region #-}
region :: (Enum a, Applicative v, Traversable v)
       => v a -- ^ Lower bound for the region
       -> v a -- ^ Higher bound for the region
       -> [v a]
region a b = sequence $ liftA2 enumFromTo a b

-- | Turns a table-space vector into a linear index, given some table size vector.
{-# INLINE flatten #-}
flatten :: (Applicative v, Integral a, Foldable v)
        => v a -- Field size vector
        -> v a -> a
flatten size vec = foldr (\(n,x) acc -> n*acc + x) 0 (liftA2 (,) size vec)

-- | Tests whether a vector is in the region given by 0 and the size vector
{-# INLINE inbounds #-}
inbounds :: (Num (v a), Ord a, Applicative v, Foldable v)
         => v a -> v a -> Bool
inbounds size vec = and (liftA2 (>=) vec 0) && and (liftA2 (<=) vec size)