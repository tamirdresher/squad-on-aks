// Squad Coordinator — routes GitHub issues to agent containers
// TODO: Implement webhook listener + agent dispatch logic

const http = require('http');

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'healthy', role: 'coordinator' }));
    return;
  }

  if (req.url === '/webhook' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      console.log('[coordinator] Received webhook event');
      // TODO: Parse event, route to appropriate agent container
      res.writeHead(200);
      res.end('ok');
    });
    return;
  }

  res.writeHead(404);
  res.end('Not found');
});

server.listen(PORT, () => {
  console.log(`[coordinator] Squad coordinator listening on port ${PORT}`);
});
