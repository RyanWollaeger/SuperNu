subroutine transport11_gamgrey(ptcl)

  use randommod
  use gridmod
  use timestepmod
  use physconstmod
  use particlemod
  use fluxmod
  implicit none
!
  type(packet),target,intent(inout) :: ptcl
!##################################################
!This subroutine passes particle parameters as input and modifies
!them through one IMC transport event (Fleck&Cummings, 1971).  If
!the puretran boolean is set to false, this routine couples to the
!analogous DDMC diffusion routine through the advance.
!##################################################
  real*8,parameter :: cinv = 1d0/pc_c
  real*8,parameter :: dt = pc_year !give grey transport infinite time
!
  real*8 :: r1, thelp,thelpinv
  real*8 :: db, dcol, d
  real*8 :: siglabfact, dcollabfact, elabfact
  real*8 :: rold, muold
! real*8 :: x1, x2, xx0
  real*8 :: help

  integer,pointer :: ix
  real*8,pointer :: r, mu, e, e0

  ix => ptcl%ix
  r => ptcl%x
  mu => ptcl%mu
  e => ptcl%e
  e0 => ptcl%e0

  if(grd_isvelocity) then
     siglabfact = 1.0d0 - mu*r*cinv
     dcollabfact = tsp_t*(1d0-mu*r*cinv)
     thelp = tsp_t
  else
     siglabfact = 1d0
     dcollabfact = 1d0
     thelp = 1d0
  endif
  thelpinv = 1d0/thelp

!
!== DISTANCE CALCULATIONS
!
!-- distance to boundary = db
  if (ix == 1) then
     db = abs(sqrt(grd_xarr(ix+1)**2-(1.0-mu**2)*r**2)-mu*r)
  elseif (mu < -sqrt(1.0d0-(grd_xarr(ix)/r)**2)) then
     db = abs(sqrt(grd_xarr(ix)**2-(1.0d0-mu**2)*r**2)+mu*r)
  else
     db = abs(sqrt(grd_xarr(ix+1)**2-(1.0d0-mu**2)*r**2)-mu*r)
  endif
!-- sanity check
  if(db/=db) stop 'transport11_gamgrey: db/=db'
!
!-- distance to fictitious collision = dcol
  if(prt_isimcanlog) then
     if(grd_capgrey(ix,1,1)>0d0) then
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        dcol = abs(log(r1)/(grd_capgrey(ix,1,1)*dcollabfact))
     else
        dcol = 2d0*abs(pc_c*dt*thelpinv) !> dcen
     endif
  else
     dcol = 2d0*abs(pc_c*dt*thelpinv) !> dcen
  endif
!
!-- minimum distance = d
!  if(tsp_it==29) write(*,*) dcol,dthm,db,dcen,ddop
  d = min(dcol,db)
!
!== END OF DISTANCE CALCULATIONS
!
!-- position, angle, time update  
  rold = r
  r = sqrt((1.0d0-mu**2)*r**2 + (d+r*mu)**2)
!  r = sqrt(r**2+d**2+2d0*d*r*mu)
  muold = mu
  mu = (rold*mu+d)/r

!-- transformation factor set
  if(grd_isvelocity) then
     elabfact = 1.0d0 - muold*rold*cinv
  else
     elabfact = 1d0
  endif
  !calculating energy deposition and density
  !
  if(.not.prt_isimcanlog) then
     grd_edep(ix,1,1) = grd_edep(ix,1,1)+e*(1.0d0-exp( &
          -grd_capgrey(ix,1,1)*siglabfact*d*thelp))*elabfact
     !--
     e = e*exp(-grd_capgrey(ix,1,1)*siglabfact*d*thelp)

  endif

!-- transformation factor reset
  if(grd_isvelocity) then
     elabfact = 1.0d0 - mu*r*cinv
  else
     elabfact = 1d0
  endif

  if (d == dcol) then  !fictitious scattering with implicit capture
     !!{{{
     r1 = rnd_r(rnd_state)
     prt_tlyrand = prt_tlyrand+1
     if(r1<=1d0.and.prt_isimcanlog) then
        prt_done = .true.
        grd_edep(ix,1,1) = grd_edep(ix,1,1) + e*elabfact
!-- velocity effects accounting
!
     else
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
        mu = 1.0-2.0*r1
        if(abs(mu)<0.0000001d0) then
           mu = 0.0000001d0
        endif
        if(grd_isvelocity) then
           mu = (mu+r*cinv)/(1.0+r*mu*cinv)
!-- velocity effects accounting
           help = 1d0/(1.0-mu*r*cinv)
!
           e = e*elabfact*help
           
        endif
!
        r1 = rnd_r(rnd_state)
        prt_tlyrand = prt_tlyrand+1
     endif
     !!}}}
  elseif (d == db) then   !------boundary crossing ----
     if (mu>=0.0d0) then!{{{
        if (ix == grd_nx) then
           prt_done = .true.
!
!-- outbound luminosity tally
!-- velocity effects accounting
!
           flx_gamluminos(1,1) = flx_gamluminos(1,1)+e/tsp_dt
           flx_gamlumdev(1,1) = flx_gamlumdev(1,1)+(e/tsp_dt)**2
           flx_gamlumnum(1,1) = flx_gamlumnum(1,1)+1
        else
           r = grd_xarr(ix+1)
           ix = ix+1
        endif
     else
        if (ix==1) then
           r = grd_xarr(ix+1)
           ix = ix+1
        else
           r = grd_xarr(ix)
           ix = ix-1
        endif
     endif!}}}
  endif

end subroutine transport11_gamgrey