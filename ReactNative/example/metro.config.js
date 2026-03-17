const { getDefaultConfig, mergeConfig } = require('@react-native/metro-config');
const path = require('path');

const apprevealPkg = path.resolve(__dirname, '..', 'appreveal');

/**
 * Metro configuration
 * Adds a watchFolder for the local react-native-appreveal package so Metro
 * can resolve it without publishing to npm.
 */
const config = {
  watchFolders: [apprevealPkg],
  resolver: {
    extraNodeModules: {
      'react-native-appreveal': apprevealPkg,
    },
  },
};

module.exports = mergeConfig(getDefaultConfig(__dirname), config);
