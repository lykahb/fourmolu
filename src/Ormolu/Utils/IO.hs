{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ViewPatterns #-}

module Ormolu.Utils.IO
  ( findClosestFileSatisfying,
    withIORefCache,
  )
where

import Control.Exception (catch, throwIO)
import Control.Monad.IO.Class
import Data.IORef
import Data.Map.Lazy (Map)
import Data.Map.Lazy qualified as M
import System.Directory
import System.FilePath
import System.IO.Error (isDoesNotExistError)

-- | Find the path to the closest file higher in the file hierarchy that
-- satisfies a given predicate.
findClosestFileSatisfying ::
  (MonadIO m) =>
  -- | The predicate that determines what we are looking for
  (FilePath -> Bool) ->
  -- | Path to the starting point for the search
  FilePath ->
  -- | Absolute path to the found file if available
  m (Maybe FilePath)
findClosestFileSatisfying isRightFile rootOfSearch = liftIO $ do
  parentDir <- takeDirectory <$> makeAbsolute rootOfSearch
  dirEntries <-
    listDirectory parentDir `catch` \case
      (isDoesNotExistError -> True) -> pure []
      e -> throwIO e
  let searchAtParentDirLevel = \case
        [] -> pure Nothing
        x : xs ->
          if isRightFile x
            then
              doesFileExist (parentDir </> x) >>= \case
                True -> pure (Just x)
                False -> searchAtParentDirLevel xs
            else searchAtParentDirLevel xs
  searchAtParentDirLevel dirEntries >>= \case
    Just foundFile -> pure . Just $ parentDir </> foundFile
    Nothing ->
      if isDrive parentDir
        then pure Nothing
        else findClosestFileSatisfying isRightFile parentDir

-- | Execute an 'IO' action but only if the given key is not found in the
-- 'IORef' cache.
withIORefCache :: (Ord k) => IORef (Map k v) -> k -> IO v -> IO v
withIORefCache cacheRef k action = do
  cache <- readIORef cacheRef
  case M.lookup k cache of
    Just v -> pure v
    Nothing -> do
      v <- action
      modifyIORef' cacheRef (M.insert k v)
      pure v
