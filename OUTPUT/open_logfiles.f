* © 2023. Triad National Security, LLC. All rights reserved.
* This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos National
* Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S. Department of
* Energy/National Nuclear Security Administration. All rights in the program are reserved by Triad
* National Security, LLC, and the U.S. Department of Energy/National Nuclear Security Administration.
* The Government is granted for itself and others acting on its behalf a nonexclusive, paid-up,
* irrevocable worldwide license in this material to reproduce, prepare. derivative works, distribute
* copies to the public, perform publicly and display publicly, and to permit others to do so.
*This file is part of SuperNu.  SuperNu is released under the terms of the GNU GPLv3, see COPYING.
*Copyright (c) 2013-2022 Ryan T. Wollaeger and Daniel R. van Rossum.  All rights reserved.
      subroutine open_logfiles
c     ------------------------
      use inputparmod
      implicit none
************************************************************************
* Open output file handles.
************************************************************************
      integer :: istat
c
      if(in_io_grabstdout) then
       write(6,*) 'write stdout to output.log'
       open(6,file='output.log',action='write',status='replace',
     &   recl=5000,iostat=istat) !write stdout to file
       if(istat/=0) stop 'parse_inputpars: open output.log error'
       call banner
      endif
c
      open(8,file='output.logdata',action='write',status='replace',
     &  recl=5000,iostat=istat) !write stdout to file
      if(istat/=0) stop 'parse_inputpars: open output.data error'
c
      end subroutine open_logfiles
c vim: fdm=marker
