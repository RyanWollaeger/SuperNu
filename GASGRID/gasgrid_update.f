      subroutine gasgrid_update(irank)
c     -------------------------------
      use gridmod
      use physconstmod
      use miscmod
      use ionsmod
      use timestepmod
      use totalsmod
      use gasgridmod
      use inputparmod
      use timingmod
      use profiledatamod
      implicit none
      integer,intent(in) :: irank
************************************************************************
* Update the part of the gas grid that depends on time and temperature.
* The non-changing part is computed in gasgrid_setup.
* The work done here is:
* - nuclear decay (energy release and chemical composition update)
* - temperature and volume
* - LTE EOS: ionization balance and electron density
* - opacities
************************************************************************
      logical,save :: first=.true.
      logical :: do_output,lexist
      integer :: i,j,k,l,ll,it,istat
      integer :: l1,l2
*     integer :: j,k,l
      real*8 :: help
*     real*8 :: hlparr(gas_ng+1)
      real*8 :: dtempfrac = 0.99d0
      real*8 :: natom1fr(dd_ncell,-2:-1) !todo: memory storage order?
      real*8 :: natom2fr(dd_ncell,-2:-1)
c-- gamma opacity
      real*8,parameter :: ye=.5d0 !todo: compute this value
c-- previous values
      real*8,allocatable,save :: tempalt(:),siggreyalt(:)
      real*8 :: hlparr(grd_nx),hlparrdd(dd_ncell)
c-- timing
      real*8 :: t0,t1
c
c-- begin
      call time(t0)
c
c-- nuclear decay
c================
c-- Get ni56 and co56 abundances on begin and end of the time step.!{{{
c-- The difference between these two has decayed.
      if(grd_isvelocity.and.gas_srctype=='none') then
c-- beginning of time step
       help = tsp_t
       call update_natomfr(help)
       forall(ll=-2:-1) natom1fr(:,ll) = dd_natom1fr(ll,:)
c-- end of time step
       call update_natomfr(tsp_t + tsp_dt)
       forall(ll=-2:-1) natom2fr(:,ll) = dd_natom1fr(ll,:)
c
c-- update the abundances for the center time
       !call update_natomfr(tsp_tcenter)
       call update_natomfr(tsp_t)
c
c-- energy deposition
       dd_nisource =  !per average atom (mix of stable and unstable)
     &   (natom1fr(:,gas_ini56) - natom2fr(:,gas_ini56)) *
     &     (pc_qhl_ni56 + pc_qhl_co56) +!ni56 that decays adds to co56
     &   (natom1fr(:,gas_ico56) - natom2fr(:,gas_ico56)) *
     &     pc_qhl_co56
c-- total, units=ergs
       dd_nisource = dd_nisource * dd_natom
c-- use gamma deposition profiles if data available
       if(prof_ntgam>0) then
c-- broken in dd
        help = sum(dd_nisource)
!       write(6,*) 'ni56 source:',help
        if(grd_ny>1 .or. grd_nz>1) stop 'gg_update: gam_prof: no 2D/3D'
        hlparr = gamma_profile(tsp_t)

        l1 = irank*dd_ncell + 1
        l2 = (irank+1)*dd_ncell
        l = 0
        ll = 0
        do i=1,grd_nx
         l = l + 1
         if(l<l1) cycle
         if(l>l2) exit
         ll = ll + 1
         hlparrdd(ll) = hlparr(i)
        enddo !i
        if(ll/=dd_ncell) stop 'gasgrid_update: ll/=dd_ncell'

        dd_nisource = help * hlparrdd
       endif
      endif
!}}}
c
c
c-- update volume
c========================================
      l1 = irank*dd_ncell + 1
      l2 = (irank+1)*dd_ncell
      l = 0
      ll = 0
      do k=1,grd_nz
      do j=1,grd_ny
      do i=1,grd_nx
       l = l + 1
       if(l<l1) cycle
       if(l>l2) exit
       ll = ll + 1
       dd_vol(ll) = grd_vol(i,j,k)
      enddo !i
      enddo !j
      enddo !k
      if(ll/=dd_ncell) stop 'gasgrid_update: ll/=dd_ncell'
c
c
c-- update density, heat capacity
c================================
      dd_rho = dd_mass/dd_vol
c-- Calculating power law heat capacity
      dd_bcoef = in_cvcoef * dd_temp**in_cvtpwr *
     &  dd_rho**in_cvrpwr
c-- temperature
      dd_ur = pc_acoef*dd_temp**4
c
c
c-- totals
c=========
c-- add initial thermal input to dd_eext
      if(tsp_it==1) then
       tot_eext = sum(dd_bcoef*dd_temp*dd_vol)
      endif
!-- total comoving material energy
      dd_emat = sum(dd_bcoef*dd_temp*dd_vol)
c
c
c
c-- compute the starting tempurature derivative in the fleck factor
      if(first .or. in_opacanaltype/='none') then
       first = .false.!{{{
c
c-- temporarily change
       dd_temp = dtempfrac*dd_temp
       if(in_opacanaltype=='none') then
        if(.not.in_noeos) call eos_update(.false.)
       endif
c
       if(in_opacanaltype/='none') then
        call analytic_opacity
       else
        if(in_ngs==0) then
         call physical_opacity
        else
         call physical_opacity_subgrid
        endif
        call opacity_planckmean
       endif
c-- change back
       dd_temp = dd_temp/dtempfrac
c
       if(.not.allocated(tempalt)) then
        allocate(tempalt(dd_ncell))
        allocate(siggreyalt(dd_ncell))
       endif
       tempalt = dd_temp
c-- per gram
       siggreyalt = dd_siggrey/dd_rho
!}}}
      endif
c
c
c
c-- solve LTE EOS
c================
      do_output = (in_pdensdump=='each' .or.
     &  (in_pdensdump=='one' .and. tsp_it==1))
      if(.not.in_noeos) call eos_update(do_output)
c
c
c
c-- calculate opacities
c======================
c-- gamma opacity
      dd_capgam = in_opcapgam*ye*dd_rho
c
c
c-- simple analytical group/grey opacities: Planck and Rosseland 
      if(in_opacanaltype/='none') then
       call analytic_opacity
      else
c-- calculate physical opacities
c-- test existence of input.opac file
       inquire(file='input.opac',exist=lexist)
       if(.not.lexist) then
c-- calculate opacities
        if(in_ngs==0) then
         call physical_opacity
        else
         call physical_opacity_subgrid
        endif
       else
c-- read in opacities
        open(4,file='input.opac',status='old',iostat=istat)!{{{
        if(istat/=0) stop 'read_opac: no file: input.opac'
c-- read header
        read(4,*,iostat=istat)
        if(istat/=0) stop 'read_opac: file empty: input.opac'
c-- read each cell individually
        do it=1,tsp_it
c-- skip delimiter
         read(4,*,iostat=istat)
         if(istat/=0) stop 'read_opac: delimiter error: input.opac'
c-- read data
         do i=1,dd_ncell
          read(4,*,iostat=istat) help,dd_sig(i),dd_cap(:,i)
          if(istat/=0) stop 'read_opac: body error: input.opac'
         enddo !i
        enddo !it
        close(4)
        write(6,*) 'read_opac: read successfully'
!}}}
       endif
       call opacity_planckmean
      endif
c
c
c-- write out opacities
c----------------------
      if(trim(in_opacdump)=='off') then !{{{
c-- donothing
      else
       open(4,file='output.opac',status='unknown',position='append')
      endif !off
c
c-- write opacity grid
      inquire(4,opened=do_output)
      if(do_output) then
c-- header
       if(tsp_it==1) write(4,'("#",3i8)') dd_ncell,tsp_nt
       write(4,'("#",3i8)') tsp_it
c-- body
       do i=1,dd_ncell
        write(4,'(1p,9999e12.4)') dd_temp(i),dd_sig(i),
     &    (dd_cap(ll,i),ll=1,gas_ng)
       enddo
c-- close file
       close(4)
      endif !do_output !}}}
c
c
c-- Calculating Fleck factor, leakage opacities
      call fleck_factor(tempalt,siggreyalt)
c-- Calculating emission probabilities for each group in each cell
      call emission_probability
c
c
c-- save previous values for gentile-fleck factor calculation in next iter
      tempalt = dd_temp
      siggreyalt = dd_siggrey/dd_rho
c
      call time(t1)
      call timereg(t_gasupd,t1-t0)
c
      end subroutine gasgrid_update
c
c
c
      subroutine update_natomfr(t)
c     ----------------------------!{{{
      use physconstmod
      use gasgridmod
      use inputparmod
      implicit none
      real*8,intent(in) :: t
************************************************************************
* update natom fractions for nuclear decay
************************************************************************
      real*8 :: expni,expco,help
c
      expni = exp(-t/pc_thl_ni56)
      expco = exp(-t/pc_thl_co56)
c
c-- update Fe
      help = 1d0 + (pc_thl_co56*expco - pc_thl_ni56*expni)/
     &  (pc_thl_ni56 - pc_thl_co56)
      if(help.lt.0) stop 'update_natomfr: Ni->Fe < 0'
      dd_natom1fr(26,:) = dd_natom0fr(gas_ini56,:)*help+!initial Ni56
     &  dd_natom0fr(gas_ico56,:)*(1d0-expco) +          !initial Co56
     &  dd_natom0fr(0,:)                                !initial Fe (stable)
c
c-- update Co56 and Co
      help = pc_thl_co56*(expni - expco)/(pc_thl_ni56 - pc_thl_co56)
      if(help.lt.0) stop 'update_natomfr: Ni->Co < 0'
c-- Co56
      dd_natom1fr(gas_ico56,:) =
     &  dd_natom0fr(gas_ini56,:)*help +  !initial Ni56
     &  dd_natom0fr(gas_ico56,:)*expco   !initial Co56
c-- Co
      dd_natom1fr(27,:) = dd_natom1fr(gas_ico56,:) +  !unstable
     &  dd_natom0fr(1,:)                                      !initial Co (stable)
c
c-- update Ni56 and Ni
c-- Ni56
      dd_natom1fr(gas_ini56,:) =
     &  dd_natom0fr(gas_ini56,:)*expni  !initial Ni56
c-- Ni
      dd_natom1fr(28,:) = dd_natom1fr(gas_ini56,:) + !unstable
     &  dd_natom0fr(2,:)                              !initial Ni (stable)
c!}}}
      end subroutine update_natomfr
