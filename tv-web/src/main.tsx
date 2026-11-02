import { AppRegistry } from 'react-native'
import App from '../../vega-app/src/App'
import './fonts.css'

AppRegistry.registerComponent('ChurchTvOs', () => App)
AppRegistry.runApplication('ChurchTvOs', { rootTag: document.getElementById('root') })
