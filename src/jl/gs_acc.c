#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include "c99.h"
#include "name.h"
#include "fail.h"
#include "types.h"
#define gs_op gs_op_t
#include "gs_defs.h"
#include "gs_local.h"
#include "comm.h"
#include "mem.h"
#include "sort.h"
#include "crystal.h"
#include "sarray_sort.h"
#include "sarray_transfer.h"
#define GS_ACC_C
#include "gs_acc.h"

GS_DEFINE_DOM_SIZES()

typedef enum { mode_plain, mode_vec, mode_many, mode_dry_run } gs_mode;

static buffer static_buffer = null_buffer;

struct pw_comm_data {
  uint n;      /* number of messages */
  uint *p;     /* message source/dest proc */
  uint *size;  /* size of message */
  uint total;  /* sum of message sizes */
};

struct pw_data {
  struct pw_comm_data comm[2];
  const uint *map[2];
  comm_req *req;
  uint buffer_size;
};

typedef void exec_fun(void *data, gs_mode mode, unsigned vn, gs_dom dom, gs_op op,
		      unsigned transpose, const void *execdata, const struct comm *comm, char *buf);

typedef void fin_fun(void *data);

struct gs_remote {
  uint buffer_size, mem_size;
  void *data;
  exec_fun *exec;
  fin_fun *fin;
};

struct gs_data {
  struct comm comm;
  const uint *map_local[2]; /* 0=unflagged, 1=all */
  const uint *flagged_primaries;
  struct gs_remote r;
  uint handle_size;
};

static char *pw_exec_recvs(char *buf, const unsigned unit_size, const struct comm *comm,
                           const struct pw_comm_data *c, comm_req *req)
{
  const uint *p, *pe, *size=c->size;
  for(p=c->p,pe=p+c->n;p!=pe;++p) {
    size_t len = *(size++)*unit_size;
#pragma acc host_data use_device(buf)
    {
      comm_irecv(req++,comm,buf,len,*p,*p);
    }
    buf += len;
  }
  return buf;
}

static char *pw_exec_sends(char *buf, const unsigned unit_size, const struct comm *comm,
                           const struct pw_comm_data *c, comm_req *req)
{
  const uint *p, *pe, *size=c->size;
  for(p=c->p,pe=p+c->n;p!=pe;++p) {
    size_t len = *(size++)*unit_size;
#pragma acc host_data use_device(buf)
    {
      comm_isend(req++,comm,buf,len,*p,comm->id);
    }
    buf += len;
  }
  return buf;
}


//
// The above is duplicated from gs.c
// The below is our "new" code
//

#include <openacc.h>

static int map_size(int *map)
{
  int i,ct=0;
  for(i=ct=0;ct<2;i++){
    if(map[i]==-1){
      ct++;
    } else {
      ct=0;
    }
  }
  printf("");
  return i;
}

void fgs_fields_acc(const sint *handle, double *u, const sint *stride, const sint *n,
		    const sint *dom, const sint *op, const sint *transpose,
		    struct gs_data **fgs_info)
{
  struct pw_data *pwd;
  struct comm    *comm;
  buffer         *buf;
  const unsigned recv = 0^*transpose, send = 1^*transpose;
  uint    i,j,k,bs,uds,dstride,dtrans,vn,m_size,fp_m_size,snd_m_size,rcv_m_size,t_m_size,diffp,bl;
  int    *map,*t_map,*fp_map,*snd_map,*rcv_map;
  double  *dbufp;
  double  t;

  // bs = vn*gs_dom_size[l_dom]*(fgs_info[*handle]->r.buffer_size);
  buf = &static_buffer;
  bs = (*n)*sizeof(double)*(fgs_info[*handle]->r.buffer_size);
  bl = bs/sizeof(double);
  buffer_reserve(buf,bs);

  // Flatten...
  dstride = *stride;
  dtrans  = *transpose;
  vn      = *n;

  // Create temp buffer for gather/scatter and send/recv
  dbufp   = (double*)buf->ptr;
  map     = (int*)(fgs_info[*handle]->map_local[0^*transpose]);
  uds     = (*stride) * (*n); // Get size of u in number of doubles
  pwd     = fgs_info[*handle]->r.data;
  comm    = &fgs_info[*handle]->comm;

  // Flatten...
  t_map      = (int*)(fgs_info[*handle]->map_local[1^*transpose]);
  fp_map     = (int*)(fgs_info[*handle]->flagged_primaries);
  snd_map    = (int*)(pwd->map[send]);
  rcv_map    = (int*)(pwd->map[recv]);
  fp_m_size  = map_size(fp_map);
  snd_m_size = map_size(snd_map);
  rcv_m_size = map_size(rcv_map);
  t_m_size   = map_size(t_map);
  m_size     = map_size(map);  


#pragma acc data pcopyin(t_map[0:t_m_size],map[0:m_size],fp_map[0:fp_m_size],snd_map[0:snd_m_size],rcv_map[0:rcv_m_size]) present(u[0:uds])
    {
#pragma acc data create(dbufp[0:bl]) if(bs!=0)
      {
  {
    // The below implementing cgs_many()/gs_aux():
    //
    // gs_aux_acc(u,mode_many,dn,fgs_dom[*dom],(gs_op_t)(*op-1),*transpose!=0,fgs_info[*handle],NULL,us);
    //

    // gs_gather_many_acc(u,u,vn,gsh->map_local[0^transpose],dom,op); 
    {
#pragma acc parallel loop gang vector present(u[0:uds],map[0:m_size]) private(t,i,j,k)
      for(k=0;k<vn;++k) {
	for(i=0;map[i]!=-1;i=j+1){
	  t = u[map[i]+k*dstride];
	  for(j=i+1;map[j]!=-1;j++){
	    t += u[map[j]+k*dstride];
	  }
	  u[map[i]+k*dstride] = t;
	}
      }
    }
      
    // --
    if(dtrans==0) {
      // wtf?!?!
      // gs_init_many_acc(u,vn,gsh->flagged_primaries,dom,op);
      {
#pragma acc parallel loop gang vector present(u[0:uds],fp_map[0:fp_m_size]) private(i,k)
	for(k=0;k<vn;++k) {
	  for(i=0;fp_map[i]!=-1;i++){
	    u[fp_map[i]+k*dstride]=0.0;
	  }
	}
      }
    }


    /* post receives */
    diffp = (double*)pw_exec_recvs((char*)dbufp,vn*sizeof(double),comm,&pwd->comm[recv],pwd->req) - dbufp;
    //    diffp = dsbufp - dbufp;    


    /* fill send buffer */
    // gs_scatter_many_to_vec_acc(sendbuf,data,vn,pwd->map[send],dom);
    {
#pragma acc parallel loop gang vector present(u[0:uds],snd_map[0:snd_m_size],dbufp[0:bl]) private(i,j,k) if(bs!=0)
      for(k=0;k<vn;k++) {
	for(i=0;snd_map[i]!=-1;i=j+1){
	  for(j=i+1;snd_map[j]!=-1;j++){
	    dbufp[k+snd_map[j]*vn + diffp] = u[snd_map[i]+k*dstride];
	  }
	}
      }
    }
    /* post sends */

    //#pragma acc update host(dbufp[0:bl])//Why update whole thing?
    pw_exec_sends((char*)(dbufp+diffp),vn*sizeof(double),comm,&pwd->comm[send],&pwd->req[pwd->comm[recv].n]);
    comm_wait(pwd->req,pwd->comm[0].n+pwd->comm[1].n);
    //#pragma acc update device(dbufp[0:diffp]) 
    /* gather using recv buffer */
    // gs_gather_vec_to_many_acc(data,buf,vn,pwd->map[recv],dom,op);
    {
#pragma acc parallel loop gang vector present(u[0:uds],rcv_map[0:rcv_m_size],dbufp[0:bl]) private(i,j,k) if(bs!=0)
      for(k=0;k<vn;k++){
	for(i=0;rcv_map[i]!=-1;i=j+1){
	  for(j=i+1;rcv_map[j]!=-1;j++){
	    u[rcv_map[i]+k*dstride] += dbufp[k+rcv_map[j]*vn];
	  }
	}
      }
    }
    // --
    // gs_scatter_many_acc(u,u,vn,gsh->map_local[1^transpose],dom); 
    {
#pragma acc parallel loop gang vector present(u[0:uds],t_map[0:t_m_size]) private(t,i,j,k)
      for(k=0;k<vn;++k) {
	for(i=0;t_map[i]!=-1;i=j+1) {
	  t=u[map[i]+k*dstride];
	  for(j=i+1;t_map[j]!=-1;j++) {
	    u[t_map[j]+k*dstride] = t;
	  }
	}
      }
    }
  }
      }}
}
