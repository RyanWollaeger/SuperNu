subroutine diffusion3(ptcl,isvacant)

  use gridmod
  use timestepmod
  use physconstmod
  use particlemod
  use inputparmod
  use fluxmod
  use totalsmod
  implicit none
!
  type(packet),target,intent(inout) :: ptcl
  logical,intent(inout) :: isvacant
!##################################################
  !This subroutine passes particle parameters as input and modifies
  !them through one DDMC diffusion event (Densmore, 2007).  If
  !the puretran boolean is set to false, this routine couples to the
  !analogous IMC transport routine through the advance. If puretran
  !is set to true, this routine is not used.
!##################################################
  real*8,parameter :: cinv = 1d0/pc_c
  integer, external :: binsrch
!
  integer :: ig, iig, iiig, imu
  logical :: lhelp
  real*8 :: r1, r2, thelp, mu0
  real*8 :: denom, denom2, denom3
  real*8 :: ddmct, tau, tcensus
  real*8 :: elabfact, dirdotu, azidotu
  real*8 :: pu, pd, pr, pl, pt, pb, pa
!-- lumped quantities
  real*8 :: emitlump, speclump
  real*8 :: caplump
  real*8 :: specig
  real*8 :: opacleak(6)
  real*8 :: mfphelp, pp
  real*8 :: resopacleak
  integer :: glump, gunlump
  integer :: glumps(grd_ng)
  real*8 :: glumpinv,dtinv,capinv(grd_ng)
  real*8 :: help
!
  integer,pointer :: ix,iy,iz
  real*8,pointer :: x,y,z,xi,om,ep,ep0,wl
!-- statement functions
  integer :: l
  real*8 :: dx,dy,dz
  dx(l) = grd_xarr(l+1) - grd_xarr(l)
  dy(l) = grd_yarr(l+1) - grd_yarr(l)
  dx(l) = grd_zarr(l+1) - grd_zarr(l)

  ix => ptcl%zsrc
  iy => ptcl%iy
  iz => ptcl%iz
  x => ptcl%rsrc
  y => ptcl%y
  z => ptcl%z
  xi => ptcl%musrc
  om => ptcl%om
  ep => ptcl%esrc
  ep0 => ptcl%ebirth
  wl => ptcl%wlsrc
!
!-- shortcut
  dtinv = 1d0/tsp_dt
  capinv = 1d0/grd_cap(:,ix,iy,iz)

!
!-- set expansion helper
  if(grd_isvelocity) then
     thelp = tsp_t
  else
     thelp = 1d0
  endif
!
!-- looking up initial group
  ig = binsrch(wl,grd_wl,grd_ng+1,in_ng)
!-- checking group bounds
  if(ig>grd_ng.or.ig<1) then
     if(g==grd_ng+1) then
        ig = grd_ng
     elseif(g==0) then
        ig = 1
     else
        stop 'diffusion3: particle group invalid'
     endif
  endif

!
!-- opacity regrouping --------------------------
  glump = 0
  gunlump = grd_ng
  glumps = 0
!
!-- find lumpable groups
  if(grd_cap(ig,ix,iy,iz)*min(dx(ix),dy(iy),dz(iz)) * &
       thelp>=prt_taulump) then
     do iig = 1, ig-1
        if(grd_cap(iig,ix,iy,iz)*min(dx(ix),dy(iy),dz(iz)) &
             *thelp >= prt_taulump) then
           glump=glump+1
           glumps(glump)=iig
        else
           glumps(gunlump)=iig
           gunlump=gunlump-1
        endif
     enddo
     do iig = ig, grd_ng
        if(grd_cap(iig,ix,iy,iz)*min(dx(ix),dy(iy),dz(iz)) &
             *thelp >= prt_taulump) then
           glump=glump+1
           glumps(glump)=iig
        else
           glumps(gunlump)=iig
           gunlump=gunlump-1
        endif
     enddo
  endif
!
  if(glump==0) then
     glump=1
     glumps(1)=ig
!
     forall(iig=2:ig) glumps(iig)=iig-1
     forall(iig=ig+1:grd_ng) glumps(iig)=iig
!
  endif

!
!-- lumping
  speclump = 0d0
  do iig = 1, glump
     iiig = glumps(iig)
     specig = grd_siggrey(ix,iy,iz)*grd_emitprob(iiig,ix,iy,iz)*capinv(iiig)
     speclump = speclump+specig
  enddo
  if(speclump>0d0.and.glump>1) then
     speclump = 1d0/speclump
  else
     speclump = 0d0
  endif

  emitlump = 0d0
  caplump = 0d0
  if(speclump>0d0) then
!
!-- calculating lumped values
     do iig = 1, glump
        iiig = glumps(iig)
        specig = grd_siggrey(ix,iy,iz)*grd_emitprob(iiig,ix,iy,iz)*capinv(iiig)
!-- emission lump
        emitlump = emitlump+grd_emitprob(iiig,ix,iy,iz)
!-- Planck x-section lump
        caplump = caplump+specig*grd_cap(iiig,ix,iy,iz)*speclump
     enddo
!-- leakage opacities
     opacleak(1) = grd_opacleak(1,ix,iy,iz)
     opacleak(2) = grd_opacleak(2,ix,iy,iz)
     opacleak(3) = grd_opacleak(3,ix,iy,iz)
     opacleak(4) = grd_opacleak(4,ix,iy,iz)
     opacleak(5) = grd_opacleak(5,ix,iy,iz)
     opacleak(6) = grd_opacleak(6,ix,iy,iz)
  else
!
!-- calculating unlumped values
     emitlump = grd_emitprob(ig,ix,iy,iz)
     caplump = grd_cap(ig,ix,iy,iz)

!-- x left (opacleakllump)
     if(ix==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix-1,iy,iz)+ &
           grd_sig(ix-1,iy,iz))*min(dx(ix-1),dy(iy),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dx(ix)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(1)=0.5d0*pp/(thelp*dx(ix))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dx(ix)+&
             (grd_sig(ix-1,iy,iz)+grd_cap(ig,ix-1,iy,iz))*dx(ix-1))*thelp
        opacleak(1)=(2d0/3d0)/(help*dx(ix)*thelp)
     endif

!-- x right (opacleakrlump)
     if(ix==grd_nx) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix+1,iy,iz)+ &
           grd_sig(ix+1,iy,iz))*min(dx(ix+1),dy(iy),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dx(ix)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(2)=0.5d0*pp/(thelp*dx(ix))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dx(ix)+&
             (grd_sig(ix+1,iy,iz)+grd_cap(ig,ix+1,iy,iz))*dx(ix+1))*thelp
        opacleak(2)=(2d0/3d0)/(help*dx(ix)*thelp)
     endif

!-- y down (opacleakdlump)
     if(iy==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix,iy-1,iz)+ &
           grd_sig(ix,iy-1,iz))*min(dx(ix),dy(iy-1),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dy(iy)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(3)=0.5d0*pp/(thelp*dy(iy))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dy(iy)+&
             (grd_sig(ix,iy-1,iz)+grd_cap(ig,ix,iy-1,iz))*dy(iy-1))*thelp
        opacleak(3)=(2d0/3d0)/(help*dy(iy)*thelp)
     endif

!-- y up (opacleakulump)
     if(iy==grd_ny) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix,iy+1,iz)+ &
           grd_sig(ix,iy+1,iz))*min(dx(ix),dy(iy+1),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dy(iy)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(4)=0.5d0*pp/(thelp*dy(iy))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dy(iy)+&
             (grd_sig(ix,iy+1,iz)+grd_cap(ig,ix,iy+1,iz))*dy(iy+1))*thelp
        opacleak(4)=(2d0/3d0)/(help*dy(iy)*thelp)
     endif

!-- z bottom (opacleakblump)
     if(iz==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix,iy,iz-1)+ &
           grd_sig(ix,iy,iz-1))*min(dx(ix),dy(iy),dz(iz-1))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dz(iz)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(5)=0.5d0*pp/(thelp*dz(iz))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dz(iz)+&
             (grd_sig(ix,iy,iz-1)+grd_cap(ig,ix,iy,iz-1))*dz(iz-1))*thelp
        opacleak(5)=(2d0/3d0)/(help*dz(iz)*thelp)
     endif

!-- z top (opacleaktlump)
     if(iz==grd_nz) then
        lhelp = .true.
     else
        lhelp = (grd_cap(ig,ix,iy,iz+1)+ &
           grd_sig(ix,iy,iz+1))*min(dx(ix),dy(iy),dz(iz+1))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ix,iy,iz)+grd_sig(ix,iy,iz))*dz(iz)*thelp
        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(6)=0.5d0*pp/(thelp*dz(iz))
     else
!-- DDMC interior
        help = ((grd_sig(ix,iy,iz)+grd_cap(ig,ix,iy,iz))*dz(iz)+&
             (grd_sig(ix,iy,iz+1)+grd_cap(ig,ix,iy,iz+1))*dz(iz+1))*thelp
        opacleak(6)=(2d0/3d0)/(help*dz(iz)*thelp)
     endif

  endif
!
!--------------------------------------------------------
!

!-- calculating time to census or event
  denom = sum(opacleak) + &
       (1d0-emitlump)*(1d0-grd_fcoef(ix,iy,iz))*caplump
  if(prt_isddmcanlog) then
     denom = denom+grd_fcoef(ix,iy,iz)*caplump
  endif

  r1 = rand()
  tau = abs(log(r1)/(pc_c*denom))
  tcensus = tsp_t+tsp_dt-ptcl%tsrc
  ddmct = min(tau,tcensus)

!
!-- calculating energy depostion and density


end subroutine diffusion3
