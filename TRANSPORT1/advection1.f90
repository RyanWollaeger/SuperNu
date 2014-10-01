subroutine advection1(pretrans,isvacant,ig,zsrc,rsrc,musrc,esrc)
  use timestepmod
  use gasgridmod
  use particlemod
  use inputparmod
  implicit none
  logical,intent(in) :: pretrans
  logical,intent(inout) :: isvacant
  integer,intent(inout) :: zsrc
  integer,intent(in) :: ig
  real*8,intent(inout) :: rsrc
  real*8,intent(in) :: musrc,esrc
!-----------------------------------------------------------------------
! This routine computes the advection of IMC particles through the
! velocity grid.  It is geometry dependent
!-----------------------------------------------------------------------
!-- advection split parameter
  real*8,parameter :: alph2 = .5d0
  logical,parameter :: partstopper = .true.
!
  integer,external :: binsrch
  integer :: zholder,zfdiff
  real*8 :: help
  integer :: ir
!
!-- different values are used before and after transport
  if(pretrans) then
    rsrc = rsrc*tsp_t/(tsp_t+alph2*tsp_dt)
  else
    rsrc = rsrc*(tsp_t + alph2*tsp_dt)/(tsp_t+tsp_dt)
  endif
!
  if (rsrc < gas_rarr(zsrc)) then
!
    zholder = binsrch(rsrc,gas_rarr,gas_nr+1,0)
!
    if(gas_isshell.and.zsrc==1) then
       prt_done = .true.
       isvacant = .true.
       gas_eleft = gas_eleft+esrc*(1d0-musrc*rsrc/pc_c)
!-- velocity effects accounting
       gas_evelo = gas_evelo+esrc*musrc*rsrc/pc_c
!
    elseif(.not.in_puretran.and.partstopper) then
       zfdiff = -1
       if(gas_isvelocity) then
          help = tsp_t
       else
          help = 1d0
       endif
       do ir = zsrc-1,zholder,-1
          if((gas_sig(ir)+gas_cap(ig,ir))*gas_drarr(ir) &
               *help>=prt_tauddmc*gas_curvcent(ir)) then
             zfdiff = ir
             exit
          endif
       enddo
       if(zfdiff.ne.-1) then
!--
          zsrc = zfdiff+1
          rsrc = gas_rarr(zsrc)
!--
       else
          zsrc = zholder
       endif
     else
       zsrc = zholder
     endif
!
  endif
end subroutine advection1
