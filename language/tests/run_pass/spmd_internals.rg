-- Copyright 2015 Stanford University
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- runs-with:
-- [["-ll:cpu", "4"]]

import "regent"

-- A test of various language features need for expressing the
-- automatic SPMD optimization.

local c = regentlib.c

struct elt {
  a : int,
  b : int,
  c : int,
  d : int,
}

task phase1(r_private : region(elt), r_ghost : region(elt))
where reads writes(r_private), reads(r_ghost) do
end

task phase2(r_private : region(elt), r_ghost : region(elt))
where reads writes(r_private.{a, b}), reduces +(r_ghost.{a, b}) do
end

task phase3(r_private : region(elt), r_ghost : region(elt))
where reads writes(r_private), reads(r_ghost) do
end

task shard(is : regentlib.list(int),
           rs_private : regentlib.list(region(elt)),
           rs_ghost : regentlib.list(region(elt)),
           rs_ghost_product : regentlib.list(regentlib.list(region(elt))))
where
  reads writes(rs_private, rs_ghost, rs_ghost_product),
  simultaneous(rs_ghost, rs_ghost_product),
  no_access_flag(rs_ghost_product)-- ,
  -- rs_private * rs_ghost,
  -- rs_private * rs_ghost_product,
  -- rs_ghost * rs_ghost_product
do
  var f = allocate_scratch_fields(rs_ghost.{a, b})
  for i in is do
    phase1(rs_private[i], rs_ghost[i])
  end

  -- -- Zero the reduction fields:
  -- for i in is do
  --   fill((with_scratch_fields(rs_ghost[i].{a, b}, f)).{a, b}, 0) -- awaits(...)
  -- end
  -- for i in is do
  --   phase2(rs_private[i], with_scratch_fields(rs_ghost[i], r.{a, b}, f))
  -- end
  -- copy((with_scratch_fields(rs_ghost.{a, b}, f)).{a, b}, rs_ghost.{a, b}, +) -- arrives(...)
  -- copy((with_scratch_fields(rs_ghost.{a, b}, f)).{a, b}, rs_ghost_product.{a, b}, +) -- arrives(...)

  -- awaits(...)
  for i in is do
    phase3(rs_private[i], rs_ghost[i])
  end
end

-- x : regentlib.list(regentlib.list(region(...))) = list_cross_product(y, z)
-- x[i][j] is the subregion of z[j] that intersects with y[i]
-- Note: This means there is NO x[i] such that x[i][j] <= x[i]
-- (because x[i][j] <= z[j] instead of y[i]).

task main()
  var lo, hi, stride = 0, 10, 3

  var r_private = region(ispace(ptr, hi-lo), elt)
  var r_ghost = region(ispace(ptr, hi-lo), elt)

  var rc = c.legion_coloring_create()
  for i = lo, hi do
    c.legion_coloring_ensure_color(rc, i)
  end
  var p_private = partition(disjoint, r_private, rc)
  var p_ghost = partition(aliased, r_ghost, rc)
  c.legion_coloring_destroy(rc)

  var rs_private = list_duplicate_partition(p_private, list_range(lo, hi))
  var rs_ghost = list_duplicate_partition(p_ghost, list_range(lo, hi))
  copy(r_private, rs_private)
  copy(r_ghost, rs_ghost)
  var rs_ghost_product = list_cross_product(rs_ghost, rs_ghost)
  must_epoch
    for i = lo, hi, stride do
      var ilo, ihi = i, regentlib.fmin(i+stride, hi)
      c.printf("launching shard ilo..ihi %d..%d\n",
               ilo, ihi)
      var is = list_range(ilo, ihi)
      var iis = list_range(0, ihi-ilo)
      var rs_p = rs_private[is]
      var rs_g = rs_ghost[is]
      var rs_g_p = rs_ghost_product[is]
      shard(iis, rs_p, rs_g, rs_g_p)
    end
  end
end
regentlib.start(main)
