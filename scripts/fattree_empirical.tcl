source "tcp-traffic-gen.tcl"

set ns [new Simulator]
set link_rate 10; #10Gbps
set mean_link_delay 0.000001; #1us
set host_delay 0.000020; #20us

set fattree_level 3;
set fattree_k 4;
set topology_x 2; # oversubcription

set flowlog [open "flow.tr" w]
set tracklog [open "track.tr" w]
set track_sample_interval 0.01
set debug_mode 0
set sim_start [clock seconds]
set flow_tot 10000; #total number of flows to generate
set flow_gen 0; #the number of flows that have been generated
set flow_fin 0; #the number of flows that have finished

set flow_cdf flow_cdf.tcl
set mean_flow_size 1711250

set connections_per_pair 3
set core_load 0.8
set p [expr int($fattree_k / 2)]
set topology_intermediate [expr int(2 * pow($p, ($fattree_level - 1)))] ; # 2*p^(L-1)
set inter_traffic_ratio [expr ($topology_intermediate - 1.0) / $topology_intermediate]
set load [expr $core_load / $inter_traffic_ratio / $topology_x]; # load of edge links
set buffer_size 210;
set rto_min 0.010;

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
	Agent/TCP set delay_emulated_ecn_threshold_ 0.000108; # n*65*1.5KB/10Gbps
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
	Agent/TCP/FullTcp set rtt_diff_threshold_dx_ 0.000012001; # 10G: 0.000002401
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
Agent/TCP set mincwnd_ 1
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
	Queue/Priority set marking_scheme_ 2;# Disable ECN (0), Per-queue ECN (1), Per-port ECN (2)
	Queue/Priority set thresh_ $ecn_thresh
}

#Queue/DCTCP set thresh_ $ecn_thresh
#Queue/DCTCP set mean_pktsize_ [expr $packet_size + 40]

################ Multipathing ###########################
$ns rtproto DV
Agent/rtProto/DV set advertInterval [expr 2 * $flow_tot] ; # sends periodic route updates every advertInterval
Node set multiPath_ 1
Classifier/MultiPath set perflow_ true
Classifier/MultiPath set debug_ false
#if {$debug_mode != 0} {
#        Classifier/MultiPath set debug_ true
#}

################ Misc ###########################
DelayLink set avoidReordering_ true

######################## Topoplgy #########################
set p [expr int($fattree_k / 2)]
set topology_servers [expr int(2 * $topology_x * pow($p, $fattree_level))] ; # 2*x*p^L
set topology_spt [expr int($p * $topology_x)] ; # servers per ToR (spt)
set topology_intermediate [expr int(2 * pow($p, ($fattree_level - 1)))] ; # 2*p^(L-1)
set topology_cores [expr int(pow($p, ($fattree_level - 1)))] ; # p^(L-1)

puts "Servers: $topology_servers"
puts "Servers per ToR: $topology_spt"
puts "Intermediate Switches per Level: $topology_intermediate"
puts "Core Switches: $topology_cores"

######### Servers #########
for {set i 0} {$i < $topology_servers} {incr i} {
        set s($i) [$ns node]
}

######### Intermediate Switches #########
for {set i 0} {$i < [expr $fattree_level - 1]} {incr i} {
        for {set j 0} {$j < $topology_intermediate} {incr j} {
                set intermediate($i,$j) [$ns node]
		}
}

######### Core Switches #########
for {set i 0} {$i < $topology_cores} {incr i} {
        set core($i) [$ns node]
}

######### Links from Servers to Edge Switches #########
for {set i 0} {$i < $topology_servers} {incr i} {
        set j [expr $i / $topology_spt] ; # ToR ID
        $ns duplex-link $s($i) $intermediate(0,$j) [set link_rate]Gb [expr $host_delay + $mean_link_delay] $switch_alg
}

######### Intermediate Links #########
for {set i 0} {$i < [expr $fattree_level - 2]} {incr i} {
		set upper_level [expr $i + 1]
		for {set j 0} {$j < $topology_intermediate} {incr j} {
				set pod_size [expr int(pow($p, $i))]
				set switch_index [expr $j % $pod_size]
				set upper_pod_size [expr int(pow($p, $upper_level))]
				set upper_pod_start [expr $j - ($j % $upper_pod_size)]
				for {set k 0} {$k < $p} {incr k} {
						$ns duplex-link $intermediate($i,$j) $intermediate($upper_level,[expr $upper_pod_start + $pod_size * $k + $switch_index]) [set link_rate]Gb [expr $mean_link_delay] $switch_alg
				}
		}
}

######### Links from Intermediate to Core Switches #########
for {set i 0} {$i < $topology_intermediate} {incr i} {
        set pod_size [expr int(pow($p, ($fattree_level - 2)))]
		set switch_index [expr $i % $pod_size]
		set core_start [expr $switch_index * $p]
        for {set j 0} {$j < $p} {incr j} {
                $ns duplex-link $intermediate([expr $fattree_level - 2],$i) $core([expr $core_start + $j]) [set link_rate]Gb [expr $mean_link_delay] $switch_alg
        }
}

#############  Agents ################
set lambda [expr ($link_rate * $load * 1000000000)/($mean_flow_size * 8.0 / $packet_size * ($packet_size + 40))]
puts "Edge link average utilization: $load"
puts "Arrival: Poisson with inter-arrival [expr 1 / $lambda * 1000] ms"
puts "Average flow size: $mean_flow_size bytes"
puts "Setting up connections ..."; flush stdout

for {set j 0} {$j < $topology_servers} {incr j} {
        for {set i 0} {$i < $topology_servers} {incr i} {
                if {$i != $j} {
                        #puts "($i, $j) "
			            puts -nonewline "($i, $j) "
                        set agtagr($i,$j) [new Agent_Aggr_pair]
                        $agtagr($i,$j) setup $s($i) $s($j) "$i $j" $connections_per_pair "TCP_pair" $source_alg
                        ## Note that RNG seed should not be zero
                        $agtagr($i,$j) set_PCarrival_process [expr $lambda / ($topology_servers - 1)] $flow_cdf [expr 17*$i+1244*$j] [expr 33*$i+4369*$j]
                        $agtagr($i,$j) attach-logfile $flowlog

                        $ns at 0.1 "$agtagr($i,$j) warmup 0.5 $packet_size"
                        $ns at 1.0 "$agtagr($i,$j) init_schedule"
                } else {
                        flush stdout
                }
        }
        flush stdout
}

puts "Initial agent creation done"
puts "Simulation started!"
$ns run
