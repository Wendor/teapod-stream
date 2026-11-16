package tun2socks

import (
	"bytes"
	"encoding/binary"
	"testing"
)

func echoRequestV4(payload []byte) []byte {
	pkt := make([]byte, 28+len(payload))
	pkt[0] = 0x45
	binary.BigEndian.PutUint16(pkt[2:4], uint16(len(pkt)))
	pkt[8] = 64
	pkt[9] = ProtocolICMP
	copy(pkt[12:16], []byte{10, 0, 0, 2})
	copy(pkt[16:20], []byte{1, 1, 1, 1})
	binary.BigEndian.PutUint16(pkt[10:12], internetChecksum(pkt[:20]))
	pkt[20] = 8
	binary.BigEndian.PutUint32(pkt[24:28], 0x12340001) // id, seq
	copy(pkt[28:], payload)
	binary.BigEndian.PutUint16(pkt[22:24], internetChecksum(pkt[20:]))
	return pkt
}

func TestICMPv4EchoReply(t *testing.T) {
	req := echoRequestV4([]byte("ping-payload"))
	resp := buildICMPv4EchoReply(req)
	if resp == nil {
		t.Fatal("no reply")
	}
	if !bytes.Equal(resp[12:16], req[16:20]) || !bytes.Equal(resp[16:20], req[12:16]) {
		t.Fatal("addresses not swapped")
	}
	if resp[20] != 0 || !bytes.Equal(resp[24:], req[24:]) {
		t.Fatal("want type 0 with the same id/seq/payload")
	}
	if internetChecksum(resp[:20]) != 0 || internetChecksum(resp[20:]) != 0 {
		t.Fatal("bad checksum")
	}
}

func TestICMPv4EchoReplyIgnoresOthers(t *testing.T) {
	reply := echoRequestV4(nil)
	reply[20] = 0
	frag := echoRequestV4(nil)
	frag[6] = 0x20 // MF
	for name, pkt := range map[string][]byte{"echo reply": reply, "fragment": frag, "short": reply[:10]} {
		if buildICMPv4EchoReply(pkt) != nil {
			t.Errorf("%s: unexpected reply", name)
		}
	}
}

func TestICMPv6EchoReply(t *testing.T) {
	icmp := []byte{128, 0, 0, 0, 0x12, 0x34, 0, 1, 'h', 'i'}
	pkt := make([]byte, 40+len(icmp))
	pkt[0] = 0x60
	binary.BigEndian.PutUint16(pkt[4:6], uint16(len(icmp)))
	pkt[6] = ProtocolICMPv6
	pkt[7] = 64
	pkt[23] = 2 // src ::2
	pkt[39] = 1 // dst ::1
	copy(pkt[40:], icmp)
	binary.BigEndian.PutUint16(pkt[42:44], icmpv6Checksum(pkt[8:24], pkt[24:40], pkt[40:]))

	resp := buildICMPv6EchoReply(pkt, 40)
	if resp == nil {
		t.Fatal("no reply")
	}
	if resp[23] != 1 || resp[39] != 2 || resp[40] != 129 || !bytes.Equal(resp[44:], icmp[4:]) {
		t.Fatal("bad reply")
	}
	if icmpv6Checksum(resp[8:24], resp[24:40], resp[40:]) != 0 {
		t.Fatal("bad checksum")
	}
}
