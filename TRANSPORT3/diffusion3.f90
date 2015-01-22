subroutine diffusion3(ptcl,ptcl2,icspec,specarr)

  use randommod
  use miscmod
  use gridmod
  use groupmod
  use timestepmod
  use physconstmod
  use particlemod
  use inputparmod
  use fluxmod
  use totalsmod
  implicit none
!
  type(packet),target,intent(inout) :: ptcl
  type(packet2),target,intent(inout) :: ptcl2
  integer,intent(inout) :: icspec
  real*8,intent(inout) :: specarr(grp_ng)
!##################################################
  !This subroutine passes particle parameters as input and modifies
  !them through one DDMC diffusion event (Densmore, 2007).  If
  !the puretran boolean is set to false, this routine couples to the
  !analogous IMC transport routine through the advance. If puretran
  !is set to true, this routine is not used.
!##################################################
  real*8,parameter :: cinv = 1d0/pc_c
  integer,external :: emitgroup
!
  integer :: iig, iiig, imu, iom
  logical :: lhelp
  real*8 :: r1, r2, thelp
  real*8 :: denom, denom2, denom3
  real*8 :: ddmct, tau, tcensus
  real*8 :: elabfact, xi, eta
!-- lumped quantities
  real*8 :: emitlump, speclump
  real*8 :: caplump
  real*8 :: specig
  real*8 :: opacleak(6)
  real*8 :: probleak(6) !leakage probabilities
  real*8 :: pa !absorption probability
  real*8 :: mfphelp, pp
  real*8 :: resopacleak
  integer :: glump, gunlump
  integer :: glumps(grp_ng)
  real*8 :: dtinv, tempinv, capgreyinv
  real*8 :: help, alb, eps, beta
!
  integer,pointer :: ix, iy, iz, ic, ig
  real*8,pointer :: x,y,z,mu,om,e,e0,wl
!-- statement functions
  integer :: l
  real*8 :: dx,dy,dz
  dx(l) = grd_xarr(l+1) - grd_xarr(l)
  dy(l) = grd_yarr(l+1) - grd_yarr(l)
  dz(l) = grd_zarr(l+1) - grd_zarr(l)

  ix => ptcl2%ix
  iy => ptcl2%iy
  iz => ptcl2%iz
  ic => ptcl2%ic
  ig => ptcl2%ig
  x => ptcl%x
  y => ptcl%y
  z => ptcl%z
  mu => ptcl%mu
  om => ptcl%om
  e => ptcl%e
  e0 => ptcl%e0
  wl => ptcl%wl
!
!-- shortcuts
  dtinv = 1d0/tsp_dt
  tempinv = 1d0/grd_temp(ic)
  capgreyinv = max(1d0/grd_capgrey(ic),0d0) !catch nans

!
!-- set expansion helper
  if(grd_isvelocity) then
     thelp = tsp_t
  else
     thelp = 1d0
  endif

!
!-- opacity regrouping --------------------------
  glump = 0
  gunlump = grp_ng
  glumps = 0
!
!-- find lumpable groups
  if(grd_cap(ig,ic)*min(dx(ix),dy(iy),dz(iz))*thelp>=prt_taulump) then
     do iig=1,grp_ng
        if(grd_cap(iig,ic)*min(dx(ix),dy(iy),dz(iz))*thelp >= prt_taulump) then
           glump=glump+1
           glumps(glump)=iig
        else
           glumps(gunlump)=iig
           gunlump=gunlump-1
        endif
     enddo
  endif
! write(0,*) ipart,istep,glump,g,ix,iy,iz

!
!-- only do this if needed
  if(glump>0 .and. icspec/=ic) then
     icspec = ic
     specarr = specintv(tempinv,0) !this is slow!
  endif

!
  if(glump==0) then
     forall(iig=1:grp_ng) glumps(iig)=iig
  endif

!
!-- lumping
  speclump = 0d0
  do iig=1,glump
     iiig = glumps(iig)
     specig = specarr(iiig)
     speclump = speclump + specig
  enddo
  if(speclump>0d0) then
     speclump = 1d0/speclump
  else
     speclump = 0d0
  endif

!write(0,*) impi,glump,speclump
!
  emitlump = 0d0
  caplump = 0d0
!-- calculate lumped values
  if(speclump>0d0) then
     if(glump==grp_ng) then!{{{
        emitlump = 1d0
        caplump = grd_capgrey(ic)
     else
        do iig=1,glump
           iiig = glumps(iig)
           specig = specarr(iiig)
!-- emission lump
           emitlump = emitlump + specig*capgreyinv*grd_cap(iiig,ic)
!-- Planck x-section lump
           caplump = caplump + specig*grd_cap(iiig,ic)*speclump
        enddo
        emitlump = min(emitlump,1d0)
     endif
!-- leakage opacities
     opacleak = grd_opacleak(:,ic)
!!}}}
  else
!
!-- calculating unlumped values
     emitlump = specint0(tempinv,ig)*capgreyinv*grd_cap(ig,ic)!{{{
     caplump = grd_cap(ig,ic)

!-- x left (opacleak(1))
     if(ix==1) then
        lhelp = .true.
     else
        l = grd_icell(ix-1,iy,iz)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix-1),dy(iy),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dx(ix)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(1)=0.5d0*pp/(thelp*dx(ix))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dx(ix)+&
             (grd_sig(l)+grd_cap(ig,l))*dx(ix-1))*thelp
        opacleak(1)=(2d0/3d0)/(help*dx(ix)*thelp)
     endif

!-- x right (opacleak(2))
     if(ix==grd_nx) then
        lhelp = .true.
     else
        l = grd_icell(ix+1,iy,iz)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix+1),dy(iy),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dx(ix)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(2)=0.5d0*pp/(thelp*dx(ix))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dx(ix)+&
             (grd_sig(l)+grd_cap(ig,l))*dx(ix+1))*thelp
        opacleak(2)=(2d0/3d0)/(help*dx(ix)*thelp)
     endif

!-- y down (opacleak(3))
     if(iy==1) then
        lhelp = .true.
     else
        l = grd_icell(ix,iy-1,iz)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix),dy(iy-1),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dy(iy)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(3)=0.5d0*pp/(thelp*dy(iy))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dy(iy)+&
             (grd_sig(l)+grd_cap(ig,l))*dy(iy-1))*thelp
        opacleak(3)=(2d0/3d0)/(help*dy(iy)*thelp)
     endif

!-- y up (opacleak(4))
     if(iy==grd_ny) then
        lhelp = .true.
     else
        l = grd_icell(ix,iy+1,iz)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix),dy(iy+1),dz(iz))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dy(iy)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(4)=0.5d0*pp/(thelp*dy(iy))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dy(iy)+&
             (grd_sig(l)+grd_cap(ig,l))*dy(iy+1))*thelp
        opacleak(4)=(2d0/3d0)/(help*dy(iy)*thelp)
     endif

!-- z bottom (opacleak(5))
     if(iz==1) then
        lhelp = .true.
     else
        l = grd_icell(ix,iy,iz-1)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix),dy(iy),dz(iz-1))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dz(iz)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(5)=0.5d0*pp/(thelp*dz(iz))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dz(iz)+&
             (grd_sig(l)+grd_cap(ig,l))*dz(iz-1))*thelp
        opacleak(5)=(2d0/3d0)/(help*dz(iz)*thelp)
     endif

!-- z top (opacleak(6))
     if(iz==grd_nz) then
        lhelp = .true.
     else
        l = grd_icell(ix,iy,iz+1)
        lhelp = (grd_cap(ig,l)+ &
           grd_sig(l))*min(dx(ix),dy(iy),dz(iz+1))* &
           thelp<prt_tauddmc
     endif
     if(lhelp) then
!-- DDMC interface
        help = (grd_cap(ig,ic)+grd_sig(ic))*dz(iz)*thelp
        alb = grd_fcoef(ic)*grd_cap(ig,ic)/ &
             (grd_cap(ig,ic)+grd_sig(ic))
        eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
        beta = 1.5d0*alb*help**2+sqrt(3d0*alb*help**2 + &
             2.25d0*alb**2*help**4)
        pp = 0.5d0*eps*beta/(beta-0.75*eps*help)
!        pp = 4d0/(3d0*help+6d0*pc_dext)
        opacleak(6)=0.5d0*pp/(thelp*dz(iz))
     else
!-- DDMC interior
        help = ((grd_sig(ic)+grd_cap(ig,ic))*dz(iz)+&
             (grd_sig(l)+grd_cap(ig,l))*dz(iz+1))*thelp
        opacleak(6)=(2d0/3d0)/(help*dz(iz)*thelp)
     endif
!}}}
  endif
!
!--------------------------------------------------------
!

!-- calculate time to census or event
  denom = sum(opacleak) + &
       (1d0-emitlump)*(1d0-grd_fcoef(ic))*caplump
  if(prt_isddmcanlog) then
     denom = denom+grd_fcoef(ic)*caplump
  endif

  r1 = rnd_r(rnd_state)
  tau = abs(log(r1)/(pc_c*denom))
  tcensus = tsp_t+tsp_dt-ptcl%t
  ddmct = min(tau,tcensus)

!
!-- calculating energy depostion and density
  if(prt_isddmcanlog) then
     grd_eraddens(ic)= grd_eraddens(ic)+e*ddmct*dtinv
  else
     grd_edep(ic) = grd_edep(ic)+e * &
          (1d0-exp(-grd_fcoef(ic)*caplump*pc_c*ddmct))
     if(grd_fcoef(ic)*caplump*min(dx(ix),dy(iy),dz(iz))*thelp>1d-6) then
        help = 1d0/(grd_fcoef(ic)*caplump)
        grd_eraddens(ic)= &
             grd_eraddens(ic)+e* &
             (1d0-exp(-grd_fcoef(ic)*caplump*pc_c*ddmct))* &
             help*cinv*dtinv
     else
        grd_eraddens(ic) = grd_eraddens(ic)+e*ddmct*dtinv
     endif
!
     if(grd_edep(ic)/=grd_edep(ic)) then
!       write(0,*) e,grd_fcoef(ic),caplump,ddmct,glump,speclump,ig,tempinv
        stop 'diffusion3: invalid energy deposition'
     endif
     e = e*exp(-grd_fcoef(ic)*caplump*pc_c*ddmct)
!!}}}
  endif

!-- updating particle time
  ptcl%t = ptcl%t+ddmct

!-- stepping particle ------------------------------------
!
!
!-- check for census
  if (ddmct /= tau) then
     ptcl2%done = .true.
     grd_numcensus(ic) = grd_numcensus(ic)+1
     return
  endif


!-- otherwise, perform event
  r1 = rnd_r(rnd_state)
  help = 1d0/denom

!-- leakage probabilities
  probleak = opacleak*help

!-- absorption probability
  if(prt_isddmcanlog) then
     pa = grd_fcoef(ic)*caplump*help
  else
     pa = 0d0
  endif

!-- absorption
  if(r1<pa) then
     ptcl2%isvacant = .true.
     ptcl2%done = .true.
     grd_edep(ic) = grd_edep(ic)+e

!-- ix->ix-1 leakage
  elseif(r1>=pa.and.r1<pa+probleak(1)) then
!{{{
     if(ix/=1) l = grd_icell(ix-1,iy,iz)

!-- sample next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(1)
        do iig=1,glump
           iiig = glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(ix==1) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix-1),dy(iy),dz(iz))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dx(ix)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dx(ix))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dx(ix)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dx(ix-1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dx(ix))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(ix==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix-1),dy(iy),dz(iz))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- ix->ix-1
        ix = ix-1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        x = grd_xarr(ix)
        r1 = rnd_r(rnd_state)
        y = (1d0-r1)*grd_yarr(iy)+r1*grd_yarr(iy+1)
        r1 = rnd_r(rnd_state)
        z = (1d0-r1)*grd_zarr(iz)+r1*grd_zarr(iz+1)
!-- must be inside cell
        y = min(y,grd_yarr(iy+1))
        y = max(y,grd_yarr(iy))
        z = min(z,grd_zarr(iz+1))
        z = max(z,grd_zarr(iz))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        xi = -max(r1,r2)
        r1 = rnd_r(rnd_state)
        eta = sqrt(1d0-xi**2)*cos(pc_pi2*r1)
        mu = sqrt(1d0-xi**2)*sin(pc_pi2*r1)
        om = atan2(eta,xi)
        if(om<0d0) om=om+pc_pi2
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(ix==1) then
!-- escaping at ix=1
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom)=flx_luminos(iiig,imu,iom)+e*dtinv
           flx_lumdev(iiig,imu,iom)=flx_lumdev(iiig,imu,iom)+(e*dtinv)**2
           flx_lumnum(iiig,imu,iom)=flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- ix->ix-1
           ix = ix-1
           ic = grd_icell(ix,iy,iz)
        endif
     endif !}}}

!-- ix->ix+1 leakage
  elseif(r1>=pa+probleak(1).and.r1<pa+sum(probleak(1:2))) then
!{{{
     if(ix/=grd_nx) l = grd_icell(ix+1,iy,iz)

!-- sampling next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(2)
        do iig = 1, glump
           iiig=glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(ix==grd_nx) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix+1),dy(iy),dz(iz))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dx(ix)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dx(ix))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dx(ix)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dx(ix+1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dx(ix))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(ix==grd_nx) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix+1),dy(iy),dz(iz))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- ix->ix+1
        ix = ix+1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        x = grd_xarr(ix+1)
        r1 = rnd_r(rnd_state)
        y = (1d0-r1)*grd_yarr(iy)+r1*grd_yarr(iy+1)
        r1 = rnd_r(rnd_state)
        z = (1d0-r1)*grd_zarr(iz)+r1*grd_zarr(iz+1)
!-- must be inside cell
        y = min(y,grd_yarr(iy+1))
        y = max(y,grd_yarr(iy))
        z = min(z,grd_zarr(iz+1))
        z = max(z,grd_zarr(iz))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        xi = max(r1,r2)
        r1 = rnd_r(rnd_state)
        eta = sqrt(1d0-xi**2)*cos(pc_pi2*r1)
        mu = sqrt(1d0-xi**2)*sin(pc_pi2*r1)
        om = atan2(eta,xi)
        if(om<0d0) om=om+pc_pi2
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(ix==grd_nx) then
!-- escaping at ix=nx
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom) = flx_luminos(iiig,imu,iom)+&
                e*dtinv
           flx_lumdev(iiig,imu,iom) = flx_lumdev(iiig,imu,iom)+&
                (e*dtinv)**2
           flx_lumnum(iiig,imu,iom) = flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- ix->ix+1
           ix = ix+1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}

!-- iy->iy-1 leakage
  elseif(r1>=pa+sum(probleak(1:2)).and.r1<pa+sum(probleak(1:3))) then
!{{{
     if(iy/=1) l = grd_icell(ix,iy-1,iz)
!-- sampling next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(3)
        do iig = 1, glump
           iiig=glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(iy==1) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix),dy(iy-1),dz(iz))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dy(iy)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dy(iy))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dy(iy)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dy(iy-1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dy(iy))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(iy==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix),dy(iy-1),dz(iz))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- iy->iy-1
        iy = iy-1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        r1 = rnd_r(rnd_state)
        x = (1d0-r1)*grd_xarr(ix)+r1*grd_xarr(ix+1)
        y = grd_yarr(iy)
        r1 = rnd_r(rnd_state)
        z = (1d0-r1)*grd_zarr(iz)+r1*grd_zarr(iz+1)
!-- must be inside cell
        x = min(x,grd_xarr(ix+1))
        x = max(x,grd_xarr(ix))
        z = min(z,grd_zarr(iz+1))
        z = max(z,grd_zarr(iz))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        eta = -max(r1,r2)
        r1 = rnd_r(rnd_state)
        xi = sqrt(1d0-eta**2)*cos(pc_pi2*r1)
        mu = sqrt(1d0-eta**2)*sin(pc_pi2*r1)
        om = atan2(eta,xi)
        if(om<0d0) om=om+pc_pi2
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(iy==1) then
!-- escaping at iy=1
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom) = flx_luminos(iiig,imu,iom)+&
                e*dtinv
           flx_lumdev(iiig,imu,iom) = flx_lumdev(iiig,imu,iom)+&
                (e*dtinv)**2
           flx_lumnum(iiig,imu,iom) = flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- iy->iy-1
           iy = iy-1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}

!-- iy->iy+1 leakage
  elseif(r1>=pa+sum(probleak(1:3)).and.r1<pa+sum(probleak(1:4))) then
!{{{
     if(iy/=grd_ny) l = grd_icell(ix,iy+1,iz)

!-- sampling next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(4)
        do iig = 1, glump
           iiig=glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(iy==grd_ny) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix),dy(iy+1),dz(iz))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dy(iy)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dy(iy))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dy(iy)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dy(iy+1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dy(iy))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(iy==grd_ny) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix),dy(iy+1),dz(iz))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- iy->iy+1
        iy = iy+1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        r1 = rnd_r(rnd_state)
        x = (1d0-r1)*grd_xarr(ix)+r1*grd_xarr(ix+1)
        y = grd_yarr(iy+1)
        r1 = rnd_r(rnd_state)
        z = (1d0-r1)*grd_zarr(iz)+r1*grd_zarr(iz+1)
!-- must be inside cell
        x = min(x,grd_xarr(ix+1))
        x = max(x,grd_xarr(ix))
        z = min(z,grd_zarr(iz+1))
        z = max(z,grd_zarr(iz))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        eta = max(r1,r2)
        r1 = rnd_r(rnd_state)
        xi = sqrt(1d0-eta**2)*cos(pc_pi2*r1)
        mu = sqrt(1d0-eta**2)*sin(pc_pi2*r1)
        om = atan2(eta,xi)
        if(om<0d0) om=om+pc_pi2
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(iy==grd_ny) then
!-- escaping at iy=ny
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom) = flx_luminos(iiig,imu,iom)+&
                e*dtinv
           flx_lumdev(iiig,imu,iom) = flx_lumdev(iiig,imu,iom)+&
                (e*dtinv)**2
           flx_lumnum(iiig,imu,iom) = flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- iy->iy+1
           iy = iy+1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}

!-- iz->iz-1 leakage
  elseif(r1>=pa+sum(probleak(1:4)).and.r1<pa+sum(probleak(1:5))) then
!{{{
     if(iz/=1) l = grd_icell(ix,iy,iz-1)

!-- sampling next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(5)
        do iig = 1, glump
           iiig=glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(iz==1) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix),dy(iy),dz(iz-1))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dz(iz)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dz(iz))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dz(iz)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dz(iz-1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dz(iz))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(iz==1) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix),dy(iy),dz(iz-1))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- iz->iz-1
        iz = iz-1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        r1 = rnd_r(rnd_state)
        x = (1d0-r1)*grd_xarr(ix)+r1*grd_xarr(ix+1)
        r1 = rnd_r(rnd_state)
        y = (1d0-r1)*grd_yarr(iy)+r1*grd_yarr(iy+1)
        z = grd_zarr(iz)
!-- must be inside cell
        x = min(x,grd_xarr(ix+1))
        x = max(x,grd_xarr(ix))
        y = min(y,grd_yarr(iy+1))
        y = max(y,grd_yarr(iy))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        mu = -max(r1,r2)
        r1 = rnd_r(rnd_state)
        om = pc_pi2*r1
        xi = sqrt(1d0-mu**2)*cos(om)
        eta = sqrt(1d0-mu**2)*sin(om)
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(iz==1) then
!-- escaping at iz=1
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom) = flx_luminos(iiig,imu,iom)+&
                e*dtinv
           flx_lumdev(iiig,imu,iom) = flx_lumdev(iiig,imu,iom)+&
                (e*dtinv)**2
           flx_lumnum(iiig,imu,iom) = flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- iz->iz-1
           iz = iz-1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}

!-- iz->iz+1 leakage
  elseif(r1>=pa+sum(probleak(1:5)).and.r1<pa+sum(probleak(1:6))) then
!{{{
     if(iz/=grd_nz) l = grd_icell(ix,iy,iz+1)

!-- sampling next group
     if(speclump<=0d0) then
        iiig = ig
     else
        r1 = rnd_r(rnd_state)
        denom2 = 0d0
        help = 1d0/opacleak(6)
        do iig = 1, glump
           iiig=glumps(iig)
           specig = specarr(iiig)
!-- calculating resolved leakage opacities
           if(iz==grd_nz) then
              lhelp = .true.
           else
              lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
                   min(dx(ix),dy(iy),dz(iz+1))*thelp<prt_tauddmc
           endif
           if(lhelp) then
!-- IMC interface or boundary
              mfphelp = (grd_cap(iiig,ic)+grd_sig(ic)) * &
                   dz(iz)*thelp
              alb = grd_fcoef(ic)*grd_cap(iiig,ic)/ &
                   (grd_cap(iiig,ic)+grd_sig(ic))
              eps = (4d0/3d0)*sqrt(3d0*alb)/(1d0+pc_dext*sqrt(3d0*alb))
              beta = 1.5d0*alb*mfphelp**2+sqrt(3d0*alb*mfphelp**2 + &
                   2.25d0*alb**2*mfphelp**4)
              pp = 0.5d0*eps*beta/(beta-0.75*eps*mfphelp)
!              pp = 4d0/(3d0*mfphelp+6d0*pc_dext)
              resopacleak = 0.5d0*pp/(thelp*dz(iz))
           else
!-- DDMC interface
              mfphelp = ((grd_sig(ic)+grd_cap(iiig,ic)) * &
                   dz(iz)+&
                   (grd_sig(l)+grd_cap(iiig,l)) * &
                   dz(iz+1))*thelp
              resopacleak = (2d0/3d0)/(mfphelp*thelp*dz(iz))
           endif
           denom2 = denom2 + specig*resopacleak*speclump*help
           if(r1<denom2) exit
        enddo
     endif

!-- sampling wavelength
     r1 = rnd_r(rnd_state)
     wl = 1d0/(r1*grp_wlinv(iiig+1)+(1d0-r1)*grp_wlinv(iiig))

!-- checking adjacent
     if(iz==grd_nz) then
        lhelp = .true.
     else
        lhelp = (grd_cap(iiig,l)+grd_sig(l)) * &
             min(dx(ix),dy(iy),dz(iz+1))*thelp<prt_tauddmc
     endif

     if(.not.lhelp) then
!-- iz->iz+1
        iz = iz+1
        ic = grd_icell(ix,iy,iz)
     else
!-- sampling x,y,z
        r1 = rnd_r(rnd_state)
        x = (1d0-r1)*grd_xarr(ix)+r1*grd_xarr(ix+1)
        r1 = rnd_r(rnd_state)
        y = (1d0-r1)*grd_yarr(iy)+r1*grd_yarr(iy+1)
        z = grd_zarr(iz+1)
!-- must be inside cell
        x = min(x,grd_xarr(ix+1))
        x = max(x,grd_xarr(ix))
        y = min(y,grd_yarr(iy+1))
        y = max(y,grd_yarr(iy))
!-- sampling direction
        r1 = rnd_r(rnd_state)
        r2 = rnd_r(rnd_state)
        mu = max(r1,r2)
        r1 = rnd_r(rnd_state)
        om = pc_pi2*r1
        xi = sqrt(1d0-mu**2)*cos(om)
        eta = sqrt(1d0-mu**2)*sin(om)
        if(grd_isvelocity) then
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
        else
           elabfact = 1d0
        endif
!-- changing from comoving frame to observer frame
        if(grd_isvelocity) then
!-- transforming mu to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
!-- transforming om to lab
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
        if(iz==grd_nz) then
!-- escaping at iz=nz
           ptcl2%isvacant = .true.
           ptcl2%done = .true.
           tot_eout = tot_eout+e
!-- luminosity tally
!-- obtaining spectrum (lab) group and polar bin
           iom = binsrch(om,flx_om,flx_nom+1,.false.)
           imu = binsrch(mu,flx_mu,flx_nmu+1,.false.)
           iiig = binsrch(wl,flx_wl,flx_ng+1,.false.)
           flx_luminos(iiig,imu,iom) = flx_luminos(iiig,imu,iom)+&
                e*dtinv
           flx_lumdev(iiig,imu,iom) = flx_lumdev(iiig,imu,iom)+&
                (e*dtinv)**2
           flx_lumnum(iiig,imu,iom) = flx_lumnum(iiig,imu,iom)+1
           return
        else
!-- converting to IMC
           ptcl2%itype = 1
           grd_methodswap(ic) = grd_methodswap(ic)+1
!-- iz->iz+1
           iz = iz+1
           ic = grd_icell(ix,iy,iz)
        endif
     endif!}}}

!-- effective scattering
  else
!!{{{
     if(glump==grp_ng) stop 'diffusion3: effective scattering with glump==ng'
!
     r1 = rnd_r(rnd_state)

     if(glump==0) then
        iiig = emitgroup(r1,ic)
     else
        denom3 = 0d0
        denom2 = 1d0-emitlump
        denom2 = 1d0/denom2
        do iig = glump+1,grp_ng
           iiig=glumps(iig)
           if(icspec==ic) then
              help = specarr(iiig)*grd_cap(iiig,ic)*capgreyinv
           else
              help = specint0(tempinv,iiig)*grd_cap(iiig,ic)*capgreyinv
           endif
           denom3 = denom3 + help*denom2
           if(denom3>r1) exit
        enddo
     endif
!
     ig = iiig
     r1 = rnd_r(rnd_state)
     wl = 1d0/((1d0-r1)*grp_wlinv(ig) + r1*grp_wlinv(ig+1))

     if((grd_sig(ic)+grd_cap(ig,ic)) * &
          min(dx(ix),dy(iy),dz(iz)) &
          *thelp < prt_tauddmc) then
        ptcl2%itype = 1
        grd_methodswap(ic) = grd_methodswap(ic)+1
!-- direction sampled isotropically           
        r1 = rnd_r(rnd_state)
        mu = 1d0 - 2d0*r1
        r1 = rnd_r(rnd_state)
        om = pc_pi2*r1
        xi = sqrt(1d0-mu**2)*cos(om)
        eta = sqrt(1d0-mu**2)*sin(om)
!-- position sampled uniformly
        r1 = rnd_r(rnd_state)
        x = r1*grd_xarr(ix+1)+(1d0-r1)*grd_xarr(ix)
        r1 = rnd_r(rnd_state)
        y = r1*grd_yarr(iy+1)+(1d0-r1)*grd_yarr(iy)
        r1 = rnd_r(rnd_state)
        z = r1*grd_zarr(iz+1)+(1d0-r1)*grd_zarr(iz)
!-- must be inside cell
        x = min(x,grd_xarr(ix+1))
        x = max(x,grd_xarr(ix))
        y = min(y,grd_yarr(iy+1))
        y = max(y,grd_yarr(iy))
        z = min(z,grd_zarr(iz+1))
        z = max(z,grd_zarr(iz))
!-- doppler and aberration corrections
        if(grd_isvelocity) then
!-- calculating transformation factors
           elabfact = 1d0+(x*xi+y*eta+z*mu)*cinv
!-- transforming z-axis direction cosine to lab
           mu = (mu+z*cinv)/elabfact
           if(mu>1d0) then
              mu = 1d0
           elseif(mu<-1d0) then
              mu = -1d0
           endif
           om = atan2(eta+y*cinv,xi+x*cinv)
           if(om<0d0) om=om+pc_pi2
!-- ELABFACT LAB RESET
           xi = sqrt(1d0-mu**2)*cos(om)
           eta= sqrt(1d0-mu**2)*sin(om)
           elabfact=1d0-(x*xi+y*eta+z*mu)*cinv
           help = 1d0/elabfact
!-- transforming wl to lab
           wl = wl*elabfact
!-- velocity effects accounting
           tot_evelo=tot_evelo+e*(1d0-help)
!
!-- transforming energy weights to lab
           e = e*help
           e0 = e0*help
        endif
     endif!}}}

  endif

end subroutine diffusion3
