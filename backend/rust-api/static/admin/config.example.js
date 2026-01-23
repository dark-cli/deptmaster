// Configuration for Admin Panel
// Copy this file to config.js and customize as needed
// config.js is gitignored, so your local changes won't be committed

window.ADMIN_CONFIG = {
    // API base URL (use relative URL if served from same origin)
    API_URL: window.location.origin + '/api',
    
    // WebSocket URL (use relative URL if served from same origin)
    WS_URL: (window.location.protocol === 'https:' ? 'wss:' : 'ws:') + '//' + window.location.host + '/ws',
    
    // Alternative: Use absolute URLs for development
    // API_URL: 'http://localhost:8000/api',
    // WS_URL: 'ws://localhost:8000/ws',
};
