source "rtt-measure.tcl"

set N 3
#set RTT 0.0001
set mean_link_delay 0.000001; #1us
set host_delay 0.000020; #20us

set simulationTime 1.0
set rttlog [open "rtt.tr" w]
set rtt_sample_interval 0.00002
set startMeasurementTime 0.003 
set stopMeasurementTime $simulationTime 
set flowClassifyTime 0.001

set lineRate 10Gb
set inputLineRate 11Gb
 
set traceSamplingInterval 0.00002
set throughputSamplingInterval 0.00002
set enableNAM 0

set buffer_size 240;
set rto_min 0.005; #2ms

set ns [new Simulator]

set arg_protocol 0; #protocol (0: DCTCP, 1: dx, 2: TIMELY-like)
set ecn_thresh 65; # (dctcp only) ECN threshold

################## Protocol Specific #########################
if {$arg_protocol == 0} {
	set source_alg Agent/TCP/FullTcp/Sack
	set switch_alg Priority
	Agent/TCP set ecn_ 1
	Agent/TCP set old_ecn_ 1
	Agent/TCP set ecn_delay_ 1;
	Agent/TCP set ecn_delay_algorithm_ 0;
	Agent/TCP set pacing_ 0;
	Agent/TCP set rtt_prioritization_ 1;
	Agent/TCP set delay_emulated_dctcp_ 5;
	Agent/TCP set delay_emulated_ecn_threshold_ 0.000144;
	Agent/TCP set dctcp_g_ 0.0625
	Agent/TCP set ecn_syn_ true
	Agent/TCP set timestamps_ true; # add 10 bytes to TCP header
	set packet_size 1450
} elseif {$arg_protocol == 1} {
	set source_alg Agent/TCP/FullTcp/Sack
	set switch_alg DropTail
	Agent/TCP set ecn_ 0
	Agent/TCP set ecn_delay_ 1;
	Agent/TCP set ecn_delay_algorithm_ 1;
	Agent/TCP set pacing_ 0;
	Agent/TCP set rtt_prioritization_ 1;
	Agent/TCP/FullTcp set rtt_diff_threshold_dx_ 0.000007201; # 10G: 0.000002401
	Agent/TCP set timestamps_ true; # add 10 bytes to TCP header
	set packet_size 1450
} elseif {$arg_protocol == 2} {
	set source_alg Agent/TCP/FullTcp/Sack
	set switch_alg Priority
	Agent/TCP set ecn_delay_ 1;
	Agent/TCP set ecn_delay_algorithm_ 2;
	Agent/TCP set pacing_ 0;
	Agent/TCP set rtt_prioritization_ 1;
	Agent/TCP set timely_patched_ 1
	Agent/TCP set timely_t_high_ 0.000500
	Agent/TCP set timely_t_ref_ 0.000150
	Agent/TCP set timely_t_low_ 0.000120
	Agent/TCP set timely_hai_n_ 5
	Agent/TCP set timely_g_ 0.0625; # EWMA for rtt_diff
	Agent/TCP set timely_inc_step_ 0.03; # Unit: pkts
	Agent/TCP set timely_beta_ 0.008
	#Agent/TCP set timely_segment_size_ 16000; # Unit: bytes
	Agent/TCP set timestamps_ true; # add 10 bytes to TCP header
	set packet_size 1450; # segment size
}

################## TCP #########################
Agent/TCP set windowInit_ 10
Agent/TCP set packetSize_ $packet_size
Agent/TCP set window_ 1000
Agent/TCP set mincwnd_ 2
Agent/TCP set slow_start_restart_ false
Agent/TCP set tcpTick_ 0.000001 ; # 1us should be enough
Agent/TCP set minrto_ $rto_min
Agent/TCP set rtxcur_init_ $rto_min ; # initial RTO
Agent/TCP set numdupacks_ 3 ; # dup ACK threshold
Agent/TCP set windowOption_ 0
Agent/TCP set ts_error_ 0.0000000

Agent/TCP/FullTcp set nodelay_ true; # disable Nagle
Agent/TCP/FullTcp set segsize_ $packet_size
Agent/TCP/FullTcp set segsperack_ 1 ; # ACK frequency
Agent/TCP/FullTcp set interval_ 0.000006 ; #delayed ACK interval

################ Queue #########################
Queue set limit_ $buffer_size
if {$arg_protocol == 0} {
	Queue/RED set bytes_ false
	Queue/RED set queue_in_bytes_ true
	Queue/RED set mean_pktsize_ [expr $packet_size + 40]
	Queue/RED set setbit_ true
	Queue/RED set gentle_ false
	Queue/RED set q_weight_ 1.0
	Queue/RED set mark_p_ 1.0
    Queue/RED set thresh_ $ecn_thresh
    Queue/RED set maxthresh_ $ecn_thresh
	Queue/Priority set mean_pktsize_ [expr $packet_size + 40]
	Queue/Priority set marking_scheme_ 2;# 0: disable; 2:per port ecn
	Queue/Priority set thresh_ $ecn_thresh
}

#Queue/DCTCP set thresh_ $ecn_thresh
#Queue/DCTCP set mean_pktsize_ [expr $packet_size + 40]

################ Multipathing ###########################
$ns rtproto DV
Agent/rtProto/DV set advertInterval 100; # sends periodic route updates every advertInterval
Node set multiPath_ 1
Classifier/MultiPath set perflow_ true
Classifier/MultiPath set debug_ false
#if {$debug_mode != 0} {
#        Classifier/MultiPath set debug_ true
#}

################ Misc ###########################
DelayLink set avoidReordering_ true

if {$enableNAM != 0} {
    set namfile [open out.nam w]
    $ns namtrace-all $namfile
}

set mytracefile [open mytracefile.tr w]
set throughputfile [open thrfile.tr w]

proc finish {} {
        global ns enableNAM namfile mytracefile throughputfile
        $ns flush-trace
        close $mytracefile
        close $throughputfile
        if {$enableNAM != 0} {
	    close $namfile
	    exec nam out.nam &
	}
	exit 0
}

proc myTrace {file} {
    global ns N traceSamplingInterval tcp
    
    set now [$ns now]
    
    for {set i 0} {$i < $N} {incr i} {
		set cwnd($i) [$tcp($i) set cwnd_]
    }
  
    puts -nonewline $file "$now $cwnd(0)"
    for {set i 1} {$i < $N} {incr i} {
		puts -nonewline $file " $cwnd($i)"
    }
    puts $file " " 
	 
    $ns at [expr $now+$traceSamplingInterval] "myTrace $file"
}

proc throughputTrace {file} {
    global ns throughputSamplingInterval qfile N
    
    set now [$ns now]
    
	puts -nonewline $file "$now "
	for {set i 0} {$i < $N} {incr i} {
		puts -nonewline $file " [expr [$qfile($i) set bdepartures_]*8/$throughputSamplingInterval/1000000]"
		$qfile($i) set bdepartures_ 0
	}
	puts $file " "	
		
    $ns at [expr $now+$throughputSamplingInterval] "throughputTrace $file"
}

set n(0) [$ns node]
set r(0) [$ns node]

for {set i 1} {$i < $N} {incr i} {
    set n($i) [$ns node]
	set r($i) [$ns node]
	set nqueue([expr ($i-1)*2]) [$ns node]
	set nqueue([expr ($i-1)*2+1]) [$ns node]
	$ns duplex-link $nqueue([expr ($i-1)*2]) $nqueue([expr ($i-1)*2+1]) $lineRate $mean_link_delay $switch_alg
	$ns duplex-link $n($i) $nqueue([expr ($i-1)*2]) $inputLineRate [expr $mean_link_delay + $host_delay] DropTail
	$ns duplex-link $r($i) $nqueue([expr ($i-1)*2+1]) $inputLineRate [expr $mean_link_delay + $host_delay] DropTail
	if {$i == 1} {
		$ns duplex-link $n(0) $nqueue([expr ($i-1)*2]) $inputLineRate [expr $mean_link_delay + $host_delay] DropTail
	} else {
		$ns duplex-link $nqueue([expr ($i-1)*2-1]) $nqueue([expr ($i-1)*2]) $lineRate $mean_link_delay $switch_alg
	}
	set qfile($i) [$ns monitor-queue $nqueue([expr ($i-1)*2+1]) $r($i) [open queue($i).tr w] $traceSamplingInterval]
}

$ns duplex-link $r(0) $nqueue([expr ($N-1)*2-1]) $inputLineRate [expr $mean_link_delay + $host_delay] DropTail
set qfile(0) [$ns monitor-queue $nqueue([expr ($N-1)*2-1]) $r(0) [open queue(0).tr w] $traceSamplingInterval]


for {set i 0} {$i < $N} {incr i} {
    set tcp($i) [new Agent/TCP/FullTcp/Sack]
    set sink($i) [new Agent/TCP/FullTcp/Sack]

    $ns attach-agent $n($i) $tcp($i)
    $ns attach-agent $r($i) $sink($i)
    
    $tcp($i) set fid_ [expr $i]
    $sink($i) set fid_ [expr $i]

	$sink($i) listen
    $ns connect $tcp($i) $sink($i)       
}

for {set i 0} {$i < $N} {incr i} {
    set ftp($i) [new Application/FTP]
    $ftp($i) attach-agent $tcp($i)    
}

$ns at $traceSamplingInterval "myTrace $mytracefile"
$ns at $throughputSamplingInterval "throughputTrace $throughputfile"

set ru [new RandomVariable/Normal]
$ru set min_ 0
$ru set max_ 1.0

for {set i 0} {$i < $N} {incr i} {
    $ns at [expr 0.03+[$ru value]/100] "$ftp($i) start"    
	#$ns at 0.03 "$ftp($i) start"    
    $ns at [expr $simulationTime] "$ftp($i) stop"
}
         
#$ns at 0.01 "measure_rtt $n(0) $r(0) {0 -1} 0.02"
		 
$ns at $simulationTime "finish"
	
$ns run