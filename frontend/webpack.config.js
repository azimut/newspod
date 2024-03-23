const path = require('path');

module.exports = {
  entry: './index.js',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'public/temp'),
    libraryTarget: 'var',
    library: 'Muh'
  },
  devtool: 'inline-source-map'
};
