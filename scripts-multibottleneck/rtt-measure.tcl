# Global Variables
# - ns: network Simulator
# - rttlog: RTT log file
# - rtt_sample_interval: RTT sampling interval

proc measure_rtt { snode dnode gid record_time } {
        global ns
        set tcp0 [new Agent/TCP]
        $tcp0 set window_ 1
		$tcp0 set packetSize_ 10
		$tcp0 set timestamps_ false
        $ns attach-agent $snode $tcp0
		
        set sink0 [new Agent/TCPSink]
        $ns attach-agent $dnode $sink0
		
        $ns connect $tcp0 $sink0
		
        set ftp0 [new Application/FTP]
        $ftp0 attach-agent $tcp0
		
        $ftp0 start
        $ns at $record_time "record_rtt $tcp0 {$gid}"
}

proc record_rtt { tcpagent gid } {
        global ns rttlog rtt_sample_interval
        set curr_rtt [$tcpagent set rtt_]
        set tick [$tcpagent set tcpTick_]
        set curr_rtt [expr $curr_rtt * $tick]
        set now [$ns now]
        puts $rttlog "$now $gid $curr_rtt"
        $ns at [expr $now + $rtt_sample_interval] "record_rtt $tcpagent {$gid}"
}
