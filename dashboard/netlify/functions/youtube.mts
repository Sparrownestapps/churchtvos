import { handleYouTubeApi } from '../../api/youtube'

export default (req: Request) => handleYouTubeApi(new URL(req.url))

export const config = { path: '/api/youtube' }
