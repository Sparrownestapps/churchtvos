// As Amazon's vega-video-sample: the automatic JSX runtime is required by @amazon-devices/react-native-w3cmedia.
module.exports = {
  presets: [['module:@react-native/babel-preset', { useTransformReactJSXExperimental: true }]],
  plugins: [['@babel/plugin-transform-react-jsx', { runtime: 'automatic' }]],
}
