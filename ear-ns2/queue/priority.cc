/*
 * Strict Priority Queueing (SP)
 *
 * Variables:
 * queue_num_: number of Class of Service (CoS) queues
 * thresh_: ECN marking threshold
 * thresh_max_: maximun ECN marking threshold for RED
 * p_max_: maximun ECN marking probability for RED
 * mean_pktsize_: configured mean packet size in bytes
 * marking_scheme_: Disable ECN (0), Per-queue ECN (1), Per-port ECN (2) and Per-port RED (3)
 */

#include "priority.h"
#include "flags.h"
#include "math.h"

#define max(arg1,arg2) (arg1>arg2 ? arg1 : arg2)
#define min(arg1,arg2) (arg1<arg2 ? arg1 : arg2)

static class PriorityClass : public TclClass {
 public:
	PriorityClass() : TclClass("Queue/Priority") {}
	TclObject* create(int, const char*const*) {
		return (new Priority);
	}
} class_priority;

void Priority::enque(Packet* p)
{
	hdr_ip *iph = hdr_ip::access(p);
	int prio = iph->prio();
	hdr_flags* hf = hdr_flags::access(p);
	int qlimBytes = qlim_ * mean_pktsize_;
    // 1<=queue_num_<=MAX_QUEUE_NUM
    queue_num_=max(min(queue_num_,MAX_QUEUE_NUM),1);

	//queue length exceeds the queue limit
	if(TotalByteLength()+hdr_cmn::access(p)->size()>qlimBytes)
	{
		drop(p);
		return;
	}

	if(prio>=queue_num_)
        prio=queue_num_-1;

	//Enqueue packet
	q_[prio]->enque(p);

    //Enqueue ECN marking
    if( (marking_scheme_==PER_QUEUE_ECN && q_[prio]->byteLength()>thresh_*mean_pktsize_)|| \
    (marking_scheme_==PER_PORT_ECN && TotalByteLength()>thresh_*mean_pktsize_) || \
	(marking_scheme_==PER_PORT_RED && (TotalByteLength()>thresh_max_*mean_pktsize_ || \
	(TotalByteLength()>thresh_*mean_pktsize_ && ((double)rand()/(double)RAND_MAX) < \
	p_max_*(TotalByteLength()-thresh_*mean_pktsize_)/(thresh_max_-thresh_)/mean_pktsize_) ) ) )
    {
        if (hf->ect()) //If this packet is ECN-capable
            hf->ce()=1;
    }
}

Packet* Priority::deque()
{
    if(TotalByteLength()>0)
	{
        //high->low: 0->7
	    for(int i=0;i<queue_num_;i++)
	    {
		    if(q_[i]->length()>0)
            {
			    Packet* p=q_[i]->deque();
		        return (p);
		    }
        }
    }

	return NULL;
}
