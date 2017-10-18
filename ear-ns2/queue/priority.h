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

#ifndef ns_priority_h
#define ns_priority_h

#define MAX_QUEUE_NUM 8

#define DISABLE_ECN 0
#define PER_QUEUE_ECN 1
#define PER_PORT_ECN 2
#define PER_PORT_RED 3

#include <string.h>
#include "queue.h"
#include "config.h"

class Priority : public Queue {
	public:
		Priority()
		{
			queue_num_=MAX_QUEUE_NUM;
			thresh_=65;
			thresh_max_=65;
			p_max_=1;
			mean_pktsize_=1500;
			marking_scheme_=DISABLE_ECN;

			//Bind variables
			bind("queue_num_", &queue_num_);
			bind("thresh_",&thresh_);
			bind("thresh_max_",&thresh_max_);
			bind("p_max_",&p_max_);
			bind("mean_pktsize_", &mean_pktsize_);
            bind("marking_scheme_", &marking_scheme_);

			//Init queues
			q_=new PacketQueue*[MAX_QUEUE_NUM];
			for(int i=0;i<MAX_QUEUE_NUM;i++)
			{
				q_[i]=new PacketQueue;
			}
		}

		~Priority()
		{
			for(int i=0;i<MAX_QUEUE_NUM;i++)
			{
				delete q_[i];
			}
			delete[] q_;
		}

	protected:
		void enque(Packet*);	// enqueue function
		Packet* deque();        // dequeue function

        PacketQueue **q_;		// underlying multi-FIFO (CoS) queues
		int mean_pktsize_;		// configured mean packet size in bytes
		int thresh_;			// single ECN marking threshold
		int thresh_max_;			// maximun ECN marking threshold for RED
		int p_max_;				// maximun ECN marking probability for RED
		int queue_num_;			// number of CoS queues. No more than MAX_QUEUE_NUM
		int marking_scheme_;	// Disable ECN (0), Per-queue ECN (1) and Per-port ECN (2)


		//Return total queue length (bytes) of all the queues
		int TotalByteLength()
		{
			int bytelength=0;
			for(int i=0; i<MAX_QUEUE_NUM; i++)
				bytelength+=q_[i]->byteLength();
			return bytelength;
		}
};

#endif
