package handlers

import "sync"

// agentCommandNotifier wakes long-polling agents when a command is committed.
// A closed channel broadcasts to every waiter; replacing it arms the next wait.
type agentCommandNotifier struct {
	mu       sync.Mutex
	channels map[uint]chan struct{}
}

func newAgentCommandNotifier() *agentCommandNotifier {
	return &agentCommandNotifier{channels: make(map[uint]chan struct{})}
}

func (n *agentCommandNotifier) waitChannel(hostID uint) <-chan struct{} {
	n.mu.Lock()
	defer n.mu.Unlock()

	ch, ok := n.channels[hostID]
	if !ok {
		ch = make(chan struct{})
		n.channels[hostID] = ch
	}
	return ch
}

func (n *agentCommandNotifier) notify(hostID uint) {
	n.mu.Lock()
	defer n.mu.Unlock()

	if ch, ok := n.channels[hostID]; ok {
		close(ch)
	}
	n.channels[hostID] = make(chan struct{})
}

var globalAgentCommandNotifier = newAgentCommandNotifier()

func notifyAgentCommand(hostID uint) {
	globalAgentCommandNotifier.notify(hostID)
}
