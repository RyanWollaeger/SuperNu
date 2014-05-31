      subroutine physical_opacity_subgrid
c     ---------------------------
c$    use omp_lib
      use physconstmod
      use inputparmod
      use ffxsmod
      use bfxsmod, only:bfxs
      use bbxsmod, only:bb_xs,bb_nline
      use ionsmod
      use gasgridmod
      use miscmod
      use timingmod
      use timestepmod, only:tsp_it
      implicit none
************************************************************************
* compute bound-free and bound-bound opacity.
************************************************************************
      integer :: ir,igs,ngs
      real*8 :: wlinv
c-- timing
      real*8 :: t0,t1,tbb,tbf,tff
c-- helper arrays
      real*8 :: grndlev(gas_nr,ion_iionmax-1,gas_nelem)
      real*8 :: grndlev2(gas_nr,ion_iionmax-1,gas_nelem)
      real*8 :: hckt(gas_nr)
      real*8 :: hlparr(gas_nr)
c-- ffxs
      real*8,parameter :: c1 = 4d0*pc_e**6/(3d0*pc_h*pc_me*pc_c**4)*
     &  sqrt(pc_pi2/(3*pc_me*pc_h*pc_c))
      real*8 :: gg,u,gff,help
      real*8 :: yend,dydx,dy !extrapolation
      integer :: iu,igg
      real*8 :: cap8
c-- bfxs
      integer :: ig,iz,ii,ie
      real*8 :: en,xs,wl,wll,wlr,kbt
      integer :: ilines,ilinee
c-- bbxs
      integer :: i,j,iwl
      real*8 :: phi,ocggrnd,expfac,wl0,dwl
      real*8 :: caphelp
c-- temporary cap array in the right order
      real*8,allocatable :: cap(:,:)  !(gas_nr,ngs)
c-- special functions
      integer :: binsrch
      real*8 :: specint, x1, x2
c-- thomson scattering
      real*8,parameter :: cthomson = 8d0*pc_pi*pc_e**4/(3d0*pc_me**2
     &  *pc_c**4)
c-- planck opacity addition condition
      logical :: planckcheck
c
c-- ion_grndlev helper array
      hckt = pc_h*pc_c/(pc_kb*gas_temp)
c
      call time(t0)
c
c-- thomson scattering
      if(.not.in_nothmson) then
       gas_sig = cthomson*gas_vals2(:)%nelec*
     &   gas_vals2(:)%natom/gas_vals2(:)%volcrp
      endif
c
c-- ground level occupation number
      do iz=1,gas_nelem
       forall(ir=1:gas_nr,ii=1:min(iz,ion_el(iz)%ni - 1))
     &   grndlev(ir,ii,iz) = ion_grndlev(iz,ir)%oc(ii)/
     &   ion_grndlev(iz,ir)%g(ii)
      enddo !iz
      do iz=1,gas_nelem
       forall(ir=1:gas_nr,ii=1:min(iz,ion_el(iz)%ni - 1))
     &   grndlev2(ir,ii,iz) = ion_grndlev(iz,ir)%oc(ii)
      enddo !iz
c
c-- find the start point: set end before first line that falls into a group
      wlr = gas_wl(1)  !in cm
      ilines = 0
      do ilinee=ilines,bb_nline-1
       wl0 = bb_xs(ilinee+1)%wl0*pc_ang  !in cm
       if(wl0 > wlr) exit
      enddo
c
c-- zero out
      gas_caprosl = 0d0
c
c-- allocate cap
      if(in_ngs==0) then
       stop 'in_ngs==0 in phys_opac_subgrid'
      elseif(in_ngs>0) then
c-- fixed subgroup number
       ngs = in_ngs
      else
c-- find biggest subgroup number for any of the groups
       i = 0
       j = 0
       do ig=1,gas_ng
        ngs = nint((gas_wl(ig+1)/gas_wl(ig) - 1d0) * abs(in_ngs))  !in_ngs stores lambda/(Delta lambda) as negative number
        j = j + ngs
        if(ngs>i) i = ngs
       enddo !ig
       ngs = max(i,1)
      endif
c-- print info in first time step
      if(tsp_it==1) write(6,*) 'ngs max|total:',i,j
      allocate(cap(gas_nr,ngs))
c
c-- bb,bf,ff opacities - group by group
      tbb = 0d0
      tbf = 0d0
      tff = 0d0
      do ig=1,gas_ng
c-- variable ngs
       if(in_ngs<0) then
        ngs = nint((gas_wl(ig+1)/gas_wl(ig) - 1d0) * abs(in_ngs)) !in_ngs stores lambda/(Delta lambda) as negative number
        ngs = max(ngs,1)
       endif
c-- right edge of the group
       wlr = gas_wl(ig+1)  !in cm
       dwl = (wlr - gas_wl(ig))/ngs
c-- bb loop start end end points
       ilines = ilinee + 1  !-- prevous end point is new starting point
       do ilinee=ilines,bb_nline-1
        wl0 = bb_xs(ilinee+1)%wl0*pc_ang  !in cm
        if(wl0 > wlr) exit
       enddo
c
       call group_opacity(ig)
c
       if(any(cap(:,:ngs)==0d0)) call warn('opacity_calc','some cap==0')
c
c-- planck average
       gas_cap(ig,:) = sum(cap(:,:ngs),dim=2)/ngs !assume evenly spaced subgroup bins
c
c-- todo: calculate gas_caprosl and gas_caprosr with cell-boundary temperature values
       if(in_noplanckweighting) then
        gas_caprosl(ig,:) = ngs/sum(1d0/cap(:,:ngs),dim=2) !assume evenly spaced subgroup bins
c-- calculate Planck function weighted Rosseland
       else
        do ir=1,gas_nr
         kbt = pc_kb*gas_temp(ir)
         do igs=1,ngs
          wll = (gas_wl(ig) + (igs-1)*dwl)
          x1 = pc_h*pc_c/((wll + dwl)*kbt)
          x2 = pc_h*pc_c/(wll*kbt)
          gas_caprosl(ig,ir) = gas_caprosl(ig,ir) +
     &      (15d0*specint(x1,x2,3)/pc_pi**4)/cap(ir,igs)
         enddo !igs
         x1 = pc_h*pc_c/(gas_wl(ig + 1)*kbt)
         x2 = pc_h*pc_c/(gas_wl(ig)*kbt)
         gas_caprosl(ig,ir) = (15d0*specint(x1,x2,3)/pc_pi**4)/
     &     gas_caprosl(ig,ir)
        enddo !ir
       endif
c
c-- combine planck and rosseland averages
       help = in_opacmixrossel
       gas_cap(ig,:) = (1d0-help)*gas_cap(ig,:) + help*gas_caprosl(ig,:)
      enddo !ig
c
c-- sanity check
      i = 0
      do ir=1,gas_nr
       do ig=1,gas_ng
        if(gas_cap(ig,ir)<=0d0) i = ior(i,1)
        if(gas_cap(ig,ir)/=gas_cap(ig,ir)) i = ior(i,2)
        if(gas_cap(ig,ir)>huge(help)) i = ior(i,4)
       enddo !ig
      enddo !ir
      if(i/=iand(i,1)) call warn('opacity_calc','some cap<=0')
      if(i/=iand(i,2)) call warn('opacity_calc','some cap==NaN')
      if(i/=iand(i,4)) call warn('opacity_calc','some cap==inf')
c
      deallocate(cap)
c
      call time(t1)
c-- register timing
      call timereg(t_opac,t1-t0)
      call timereg(t_bb,tbb)
      call timereg(t_bf,tbf)
      call timereg(t_ff,tff)
c
      contains
c
      subroutine group_opacity(ig)
c     ----------------------------!{{{
      implicit none
      integer,intent(in) :: ig
************************************************************************
* Calculate bb,bf,ff opacity for one wl group using a refined wl subgrid
************************************************************************
      integer :: igs
      real*8 :: dwl,wll
      real*8 :: t0,t1,t2,t3
c
c-- left group-boundary wavelength
      wll = gas_wl(ig)  !in cm
c-- subgroup width
      dwl = (gas_wl(ig+1) - wll)/ngs
c
c-- reset
      cap = 0d0
c
c-- bound-bound
      call time(t0)
      if(.not. in_nobbopac) then
      igs = 1!{{{
c$omp parallel do
c$omp& schedule(static)
c$omp& private(iz,ii,wl0,wlinv,phi,caphelp,expfac,ocggrnd)
c$omp& firstprivate(grndlev,hckt,igs)
c$omp& shared(cap)
       do i=ilines,ilinee
        iz = bb_xs(i)%iz
        ii = bb_xs(i)%ii
        wl0 = bb_xs(i)%wl0*pc_ang  !in cm
        wlinv = 1d0/wl0  !in cm
c-- igs pointer
        do igs=igs,ngs-1
         if(wl0 <= wll+igs*dwl) exit
        enddo
c-- profile function
        phi = 1d0/dwl
!       write(6,*) 'phi',phi
c-- evaluate caphelp
        do ir=1,gas_nr
         if(.not.gas_vals2(ir)%opdirty) cycle !opacities are still valid
         ocggrnd = grndlev(ir,ii,iz)
c-- oc high enough to be significant?
*        if(ocggrnd<=1d-30) cycle !todo: is this _always_ low enoug? It is in the few tests I did.
         if(ocggrnd<=0d0) cycle !todo: is this _always_ low enoug? It is in the few tests I did.
         expfac = 1d0 - exp(-hckt(ir)*wlinv)
         caphelp = phi*bb_xs(i)%gxs*ocggrnd * wl0**2/pc_c *
     &     exp(-bb_xs(i)%chilw*hckt(ir))*expfac
!        if(caphelp==0.) write(6,*) 'cap0',cap(ir,igs),phi,
!    &     bb_xs(i)%gxs,ocggrnd,exp(-bb_xs(i)%chilw*hckt(ir)),expfac
         if(caphelp==0.) cycle
         cap(ir,igs) = cap(ir,igs) + caphelp
        enddo !ir
c-- vectorized alternative is slower
cslow   where(gas_vals2(:)%opdirty .and. grndlev(:,ii,iz)>1d-30)
cslow    cap(:,igs) = cap(:,igs) +
cslow&     phi*bb_xs(i)%gxs*grndlev(:,ii,iz)*
cslow&     exp(-bb_xs(i)%chilw*hckt(:))*(1d0 - exp(-wlinv*hckt(:)))
cslow   endwhere
       enddo !i
c$omp end parallel do !}}}
      endif !in_nobbopac
c
c
c-- bound-free
      call time(t1)
      if(.not. in_nobfopac) then
c$omp parallel do!{{{
c$omp& schedule(static)
c$omp& private(wl,en,ie,xs)
c$omp& firstprivate(grndlev2)
c$omp& shared(cap)
       do igs=1,ngs
        wl = wll + (igs-.5d0)*dwl !-- subgroup bin center value
        en = pc_h*pc_c/(pc_ev*wl) !photon energy in eV
        do iz=1,gas_nelem
         do ii=1,min(iz,ion_el(iz)%ni - 1) !last stage is bare nucleus
          ie = iz - ii + 1
          xs = bfxs(iz,ie,en)
          if(xs==0d0) cycle
          forall(ir=1:gas_nr)
*         forall(ir=1:gas_nr,gas_vals2(ir)%opdirty)
     &      cap(ir,igs) = cap(ir,igs) +
     &      xs*pc_mbarn*grndlev2(ir,ii,iz)
         enddo !ie
        enddo !iz
!       write(6,*) 'wl done:',igs !DEBUG
!       write(6,*) cap(:,igs) !DEBUG
       enddo !igs
c$omp end parallel do!}}}
      endif !in_nobfopac
c
c
c-- free-free
      call time(t2)
      if(.not. in_noffopac) then
c-- simple variant: nearest data grid point!{{{
       hlparr = (gas_vals2%natom/gas_vals2%vol)**2*gas_vals2%nelec
c$omp parallel do
c$omp& schedule(static)
c$omp& private(wl,wlinv,u,iu,help,cap8,gg,igg,gff,yend,dydx,dy)
c$omp& firstprivate(hckt,hlparr)
c$omp& shared(cap)
       do igs=1,ngs
        wl = wll + (igs-.5d0)*dwl !-- subgroup bin center value
        wlinv = 1d0/wl  !in cm
c-- gcell loop
        do ir=1,gas_nr
         u = hckt(ir)*wlinv
         iu = nint(10d0*(log10(u) + 4d0)) + 1
c
         help = c1*sqrt(hckt(ir))*(1d0 - exp(-u))*wl**3*hlparr(ir)
         if(iu<1 .or. iu>ff_nu) then
          call warn('opacity_calc','ff: iu out of data limit')
          iu = min(iu,ff_nu)
          iu = max(iu,1)
         endif
c-- element loop
         cap8 = 0d0
         do iz=1,gas_nelem
          gg = iz**2*pc_rydberg*hckt(ir)
          igg = nint(5d0*(log10(gg) + 4d0)) + 1
c-- gff is approximately constant in the low igg data-limit, do trivial extrapolation:
          igg = max(igg,1)
          if(igg<=ff_ngg) then
           gff = ff_gff(iu,igg)
          else
c-- extrapolate
           yend = ff_gff(iu,ff_ngg)
           dydx = .5d0*(yend - ff_gff(iu,ff_ngg-2))
           dy = dydx*(igg - ff_ngg)
           if(abs(dy)>abs(yend - 1d0) .or. !don't cross asymptotic value
     &       sign(1d0,dy)==sign(1d0,yend - 1d0)) then !wrong slope
c-- asymptotic value
            gff = 1d0
           else
            gff = yend + dydx*(igg - ff_ngg)
           endif
          endif
c-- cross section
          cap8 = cap8 + help*gff*iz**2*gas_vals2(ir)%natom1fr(iz)
         enddo !iz
         cap(ir,igs) = cap(ir,igs) + cap8
        enddo !ir
       enddo !igs
c$omp end parallel do!}}}
      endif !in_noffopac!}}}
c
      call time(t3)
      t_bb = t_bb + (t1-t0)
      t_bf = t_bf + (t2-t1)
      t_ff = t_ff + (t3-t2)
      end subroutine group_opacity
c
      end subroutine physical_opacity_subgrid
