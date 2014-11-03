      module mpimod
c     -------------
      implicit none
      INCLUDE 'mpif.h'
c
      integer,parameter :: impi0 = 0 !the master rank
      integer :: impi !mpi rank
      integer :: nmpi !number of mpi tasks
      integer,private :: ierr
c
      contains
c
c
c
      subroutine bcast_permanent
c     --------------------------!{{{
      use inputparmod
      use gasgridmod,nx=>gas_nx,ny=>gas_ny,nz=>gas_nz
      use particlemod
      use timestepmod
      implicit none
************************************************************************
* Broadcast the data that does not evolve over time (or temperature).
* Also once the constants are broadcasted, all allocatable arrays are
* allocated.
************************************************************************
      integer :: n
      logical,allocatable :: lsndvec(:)
      integer,allocatable :: isndvec(:)
      real*8,allocatable :: sndvec(:)
c
c-- broadcast constants
c-- logical
      n = 6
      allocate(lsndvec(n))
      if(impi==impi0) lsndvec = (/gas_isvelocity,in_puretran,
     &  prt_isimcanlog,prt_isddmcanlog,in_norestart,in_noeos/)
      call mpi_bcast(lsndvec,n,MPI_LOGICAL,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      gas_isvelocity = lsndvec(1)
      in_puretran = lsndvec(2)
      prt_isimcanlog = lsndvec(3)
      prt_isddmcanlog = lsndvec(4)
      in_norestart = lsndvec(5)
      in_noeos = lsndvec(6)
      deallocate(lsndvec)
c
c-- integer
      n = 12
      allocate(isndvec(n))
      if(impi==impi0) isndvec = (/in_igeom,nx,ny,nz,gas_ng,
     &  prt_npartmax,in_nomp,tsp_nt,in_ntres,tsp_ntres,
     &  prt_ninitnew,in_ng/)
      call mpi_bcast(isndvec,n,MPI_INTEGER,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      in_igeom     = isndvec(1) 
      nx           = isndvec(2)
      ny           = isndvec(3)
      nz           = isndvec(4)
      gas_ng       = isndvec(5)
      prt_npartmax = isndvec(6)
      in_nomp      = isndvec(7)
      tsp_nt       = isndvec(8)
      in_ntres     = isndvec(9)
      tsp_ntres    = isndvec(10)
      prt_ninitnew = isndvec(11)
      in_ng        = isndvec(12)
      deallocate(isndvec)
c
c-- real*8
      n = 3
      allocate(sndvec(n))
      if(impi==impi0) sndvec = (/prt_tauddmc,prt_taulump,tsp_t/)
      call mpi_bcast(sndvec,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      prt_tauddmc = sndvec(1)
      prt_taulump = sndvec(2)
      tsp_t = sndvec(3)
      deallocate(sndvec)
c
c-- character
      call mpi_bcast(gas_srctype,4,MPI_CHARACTER,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_opacanaltype,4,MPI_CHARACTER,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(prt_tauvtime,4,MPI_CHARACTER,
     &  impi0,MPI_COMM_WORLD,ierr)
c
c
c$    if(in_nomp/=0) call omp_set_num_threads(in_nomp)
c
c
c-- allocate all arrays. These are deallocated in dealloc_all.f
      if(impi/=impi0) then
       allocate(gas_nvolinit(nx,ny,nz))
       allocate(gas_xarr(nx+1))
       allocate(gas_yarr(ny+1))
       allocate(gas_zarr(nz+1))
       allocate(gas_evolinit(nx,ny,nz))
       allocate(gas_wl(gas_ng+1))
      endif
c
c-- broadcast data
      call mpi_bcast(gas_nvolinit,nx*ny*nz,MPI_INTEGER,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_xarr,nx+1,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_yarr,ny+1,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_zarr,nz+1,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_evolinit,nx*ny*nz,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_wl,gas_ng+1,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c!}}}
      end subroutine bcast_permanent
c
c
c
      subroutine bcast_nonpermanent
c     ------------------------!{{{
      use gasgridmod,nx=>gas_nx,ny=>gas_ny,nz=>gas_nz
      use particlemod
      use timestepmod
      implicit none
************************************************************************
* Broadcast the data that changes with time/temperature.
*-- scalars:
*-- real
* real*8 :: tsp_t
* real*8 :: tsp_dt
* real*8 :: gas_esurf
* real*8 :: gas_etot
* real*8 :: gas_eext
*-- integer
* integer :: prt_nnew
* integer :: prt_nsurf
* integer :: prt_nexsrc
*--
*
*-- arrays:
*-- real
* real*8 :: gas_temp(nx,ny,nz)
* real*8 :: gas_nvol(nx,ny,nz)
* real*8 :: gas_nvolex(nx,ny,nz)
* real*8 :: gas_emit(nx,ny,nz)
* real*8 :: gas_emitex(nx,ny,nz)
* real*8 :: gas_fcoef(nx,ny,nz)
* real*8 :: gas_sig(nx,ny,nz)
* real*8 :: gas_emitprob(gas_ng,nx,ny,nz)
* real*8 :: gas_opacleak(6,nx,ny,nz)
* real*8 :: gas_cap(gas_ng,nx,ny,nz)
*-- integer
* integer :: gas_methodswap(nx,ny,nz)
*
************************************************************************
      integer :: n
      integer,allocatable :: isndvec(:)
      real*8,allocatable :: sndvec(:)

c-- variables to be reduced -----------------------------------
c-- dim==1,2
      if(impi/=impi0 .and. .not.allocated(gas_numcensus)) then
         allocate(gas_numcensus(nx,ny,nz))
         allocate(gas_edep(nx,ny,nz))
         allocate(gas_eraddens(nx,ny,nz))
         allocate(gas_luminos(gas_ng))
         allocate(gas_lumdev(gas_ng))
         allocate(gas_lumnum(gas_ng))
         allocate(gas_methodswap(nx,ny,nz))
      endif
!      call mpi_bcast(gas_edep,nx*ny*nz,MPI_REAL8,
!     &  impi0,MPI_COMM_WORLD,ierr)
!      call mpi_bcast(gas_numcensus,nx*ny*nz,MPI_INTEGER,
!     &  impi0,MPI_COMM_WORLD,ierr)
!      call mpi_bcast(gas_eraddens,nx*ny*nz,MPI_REAL8,
!     &  impi0,MPI_COMM_WORLD,ierr)
c--------------------------------------------------------------
c
c-- integer
      n = 3
      allocate(isndvec(n))
      if(impi==impi0) isndvec = (/prt_nnew,prt_nsurf,
     & prt_nexsrc/)
      call mpi_bcast(isndvec,n,MPI_INTEGER,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      prt_nnew = isndvec(1)
      prt_nsurf = isndvec(2)
      prt_nexsrc = isndvec(3)
      deallocate(isndvec)
c
c-- real*8
      n = 4
      allocate(sndvec(n))
      if(impi==impi0) sndvec = (/tsp_t,tsp_dt,gas_esurf,
     & gas_etot/)
      call mpi_bcast(sndvec,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      tsp_t = sndvec(1)
      tsp_dt = sndvec(2)
      gas_esurf = sndvec(3)
      gas_etot = sndvec(4)
      deallocate(sndvec)
c
c-- initial send of gas_eext
      if(tsp_it==1) then
         call mpi_bcast(gas_eext,1,MPI_REAL8,impi0,MPI_COMM_WORLD,ierr)
      endif
c
c-- allocate all arrays. These are deallocated in dealloc_all.f
      if(impi/=impi0 .and. .not.allocated(gas_temp)) then
       allocate(gas_temp(nx,ny,nz))
       allocate(gas_nvol(nx,ny,nz))
       allocate(gas_nvolex(nx,ny,nz))
       allocate(gas_emit(nx,ny,nz))
       allocate(gas_emitex(nx,ny,nz))
c
       allocate(gas_fcoef(nx,ny,nz))
       allocate(gas_sig(nx,ny,nz))
       allocate(gas_siggrey(nx,ny,nz))
       allocate(gas_emitprob(gas_ng,nx,ny,nz))
       allocate(gas_opacleak(6,nx,ny,nz))
       allocate(gas_cap(gas_ng,nx,ny,nz))
      endif
c
      n = nx*ny*nz
      call mpi_bcast(gas_temp,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_nvol,n,MPI_INTEGER,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_nvolex,n,MPI_INTEGER,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_emit,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_emitex,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c
      call mpi_bcast(gas_siggrey,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c
      call mpi_bcast(gas_fcoef,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_sig,n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_emitprob,n*gas_ng,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_opacleak,6*n,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
      call mpi_bcast(gas_cap,n*gas_ng,MPI_REAL8,
     &  impi0,MPI_COMM_WORLD,ierr)
c!}}}
      end subroutine bcast_nonpermanent
c
c
c
      subroutine reduce_tally
c     -----------------------!{{{
      use gasgridmod,nx=>gas_nx,ny=>gas_ny,nz=>gas_nz
      use timingmod
      implicit none
************************************************************************
* Reduce the results from particle_advance that are needed for the
* temperature correction.
* - t_pckt_stat !min,mean,max
* 
*-- dim==0
* real*8 :: gas_erad
* real*8 :: gas_eright
* real*8 :: gas_eleft
*-- dim==1
* integer :: gas_lumnum(ng)
* real*8 :: gas_luminos(ng)
* real*8 :: gas_lumdev(ng)
*-- dim==3
* integer :: gas_numcensus(nx,ny,nz)
* real*8 :: gas_edep(nx,ny,nz)
* real*8 :: gas_eraddens(nx,ny,nz)
************************************************************************
      integer :: n
      integer,allocatable :: isndvec(:)
      real*8,allocatable :: sndvec(:),rcvvec(:)
      integer :: isnd3(nx,ny,nz)
      real*8 :: snd3(nx,ny,nz)
      real*8 :: help

c
c-- dim==0
      n = 5
      allocate(sndvec(n))
      allocate(rcvvec(n))
      !if(impi==impi0) 
      sndvec = (/gas_erad,gas_eright,gas_eleft,gas_eext,gas_evelo/)
      call mpi_reduce(sndvec,rcvvec,n,MPI_REAL8,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
c-- copy back
      if(impi==0) then
       gas_erad = rcvvec(1)/dble(nmpi)
       gas_eright = rcvvec(2)/dble(nmpi)
       gas_eleft = rcvvec(3)/dble(nmpi)
       gas_eextav = rcvvec(4)/dble(nmpi)
       gas_eveloav = rcvvec(5)/dble(nmpi)
      else
       gas_erad = 0d0
       gas_eright = 0d0
       gas_eleft = 0d0
c-- rtw: can't copy back 0 to eext or evelo.
      endif !impi
      deallocate(sndvec)
      deallocate(rcvvec)
c
c-- dim==1
      allocate(isndvec(gas_ng))
      isndvec = gas_lumnum
      call mpi_reduce(isndvec,gas_lumnum,gas_ng,MPI_INTEGER,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
      deallocate(isndvec)
c
      allocate(sndvec(gas_ng))
      sndvec = gas_luminos
      call mpi_reduce(sndvec,gas_luminos,gas_ng,MPI_REAL8,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
      gas_luminos = gas_luminos/dble(nmpi)
c
      sndvec = gas_lumdev
      call mpi_reduce(sndvec,gas_lumdev,gas_ng,MPI_REAL8,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
      gas_lumdev = gas_lumdev/dble(nmpi)
      deallocate(sndvec)
c
c-- dim==3
      n = nx*ny*nz
      isnd3 = gas_numcensus
      call mpi_reduce(isnd3,gas_numcensus,n,MPI_INTEGER,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
c
      snd3 = gas_edep
      call mpi_allreduce(snd3,gas_edep,n,MPI_REAL8,MPI_SUM,
     &  MPI_COMM_WORLD,ierr)
      gas_edep = gas_edep/dble(nmpi)
c
      isnd3 = gas_methodswap
      call mpi_reduce(isnd3,gas_methodswap,n,MPI_INTEGER,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
c
      snd3 = gas_eraddens
      call mpi_reduce(snd3,gas_eraddens,n,MPI_REAL8,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
      gas_eraddens = gas_eraddens/dble(nmpi)
c
c-- timing statistics
      help = t_pckt_stat(1)
      call mpi_reduce(help,t_pckt_stat(1),1,MPI_REAL8,MPI_MIN,
     &  impi0,MPI_COMM_WORLD,ierr)
      help = t_pckt_stat(2)/nmpi
      call mpi_reduce(help,t_pckt_stat(2),1,MPI_REAL8,MPI_SUM,
     &  impi0,MPI_COMM_WORLD,ierr)
      help = t_pckt_stat(3)
      call mpi_reduce(help,t_pckt_stat(3),1,MPI_REAL8,MPI_MAX,
     &  impi0,MPI_COMM_WORLD,ierr)
c!}}}
      end subroutine reduce_tally
c
c
c
      subroutine scatter_restart_data
c     -------------------------------!{{{
      use particlemod
************************************************************************
* scatter restart data from master rank to subordinate ranks.
* allows for restart at some time step, tsp_it.
************************************************************************
c-- helper variables
      integer :: isq
      real :: hlp
c
c-- scattering part vacancy
      call mpi_scatter(prt_tlyvacant,prt_npartmax,MPI_LOGICAL,
     &     prt_isvacant,prt_npartmax,MPI_LOGICAL,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part zone
      call mpi_scatter(prt_tlyzsrc,prt_npartmax,MPI_INTEGER,
     &     prt_particles%zsrc,prt_npartmax,MPI_INTEGER,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part transport index
      call mpi_scatter(prt_tlyrtsrc,prt_npartmax,MPI_INTEGER,
     &     prt_particles%rtsrc,prt_npartmax,MPI_INTEGER,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part position
      call mpi_scatter(prt_tlyrsrc,prt_npartmax,MPI_REAL8,
     &     prt_particles%rsrc,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part direction
      call mpi_scatter(prt_tlymusrc,prt_npartmax,MPI_REAL8,
     &     prt_particles%musrc,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part time
      call mpi_scatter(prt_tlytsrc,prt_npartmax,MPI_REAL8,
     &     prt_particles%tsrc,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part energy
      call mpi_scatter(prt_tlyesrc,prt_npartmax,MPI_REAL8,
     &     prt_particles%esrc,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part birth energy
      call mpi_scatter(prt_tlyebirth,prt_npartmax,MPI_REAL8,
     &     prt_particles%ebirth,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering part wavelength
      call mpi_scatter(prt_tlywlsrc,prt_npartmax,MPI_REAL8,
     &     prt_particles%wlsrc,prt_npartmax,MPI_REAL8,impi0,
     &     MPI_COMM_WORLD,ierr)
c
c-- scattering rand() count
      call mpi_scatter(prt_tlyrandarr,1,MPI_INTEGER,
     &     prt_tlyrand,1,MPI_INTEGER,impi0,MPI_COMM_WORLD,ierr)
c
c-- iterating to correct rand() count
      do isq = 1, prt_tlyrand-1
         hlp = rand()
      enddo
c
c-- deallocations



c!}}}
      end subroutine scatter_restart_data
c
c
c
      subroutine collect_restart_data
c     -------------------------------!{{{
      use particlemod
************************************************************************
* send particle array info and number of rand calls to master rank.
* allows for restart at some time step, tsp_it.
* Files written here to avoid too many allocations of large particle
* arrays.
************************************************************************
c
c-- gathering part vacancy
      call mpi_gather(prt_isvacant,prt_npartmax,MPI_LOGICAL,
     &     prt_tlyvacant,prt_npartmax,MPI_LOGICAL,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part zone
      call mpi_gather(prt_particles%zsrc,prt_npartmax,MPI_INTEGER,
     &     prt_tlyzsrc,prt_npartmax,MPI_INTEGER,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part transport index
      call mpi_gather(prt_particles%zsrc,prt_npartmax,MPI_INTEGER,
     &     prt_tlyrtsrc,prt_npartmax,MPI_INTEGER,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part position
      call mpi_gather(prt_particles%rsrc,prt_npartmax,MPI_REAL8,
     &     prt_tlyrsrc,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part direction
      call mpi_gather(prt_particles%musrc,prt_npartmax,MPI_REAL8,
     &     prt_tlymusrc,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part time
      call mpi_gather(prt_particles%tsrc,prt_npartmax,MPI_REAL8,
     &     prt_tlytsrc,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part energy
      call mpi_gather(prt_particles%esrc,prt_npartmax,MPI_REAL8,
     &     prt_tlyesrc,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part birth energy
      call mpi_gather(prt_particles%ebirth,prt_npartmax,MPI_REAL8,
     &     prt_tlyebirth,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c-- gathering part wavelength
      call mpi_gather(prt_particles%wlsrc,prt_npartmax,MPI_REAL8,
     &     prt_tlywlsrc,prt_npartmax,MPI_REAL8,impi0,MPI_COMM_WORLD,
     &     ierr)
c
c
c====
c
c-- gathering rand() counts
      call mpi_gather(prt_tlyrand,1,MPI_INTEGER,prt_tlyrandarr,1,
     &     MPI_INTEGER,impi0,MPI_COMM_WORLD,ierr)
c
c-- deallocations


c!}}}
      end subroutine collect_restart_data    
c
      end module mpimod
