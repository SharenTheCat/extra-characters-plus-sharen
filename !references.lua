--- @meta
--[[
    This file contains some functions ported over from the source code
    They should be close to if not fully accurate to how they are supposed to functions
    However, do not just directly use or edit these, they are for future reference
    These aren't optimized, they're a direct port from the source code, so please optimize your code if you copy any of them
    I might port some more useful ones, don't include this file on release
]]

--- @param pos Vec3f
--- @param height number
--- @return number
--[[
 *  Finds the ceiling from a vec3f horizontally and a height (with 80 vertical buffer).
 *  Prevents exposed ceiling bug
]]
function vec3f_mario_ceil(pos, height)
    if (gLevelValues.fixCollisionBugs ~= 0) then
        height = math.max(height + 80.0, pos.y - 2)
        return find_ceil_height(pos.x, height, pos.z)
    else
        return find_ceil_height(pos.x, height + 80.0, pos.z)
    end
end

--- @param m MarioState
--- @param wall Surface
--- @param intendedPos Vec3f
--- @param nextPos Vec3f
--- @return integer
function check_ledge_grab(m, wall, intendedPos, nextPos)
    if not m then return 0 end
    local ledgeFloor
    local ledgePos
    local displacementX
    local displacementZ

    if m.vel.y > 0 then
        return 0
    end

    displacementX = nextPos.x - intendedPos.x
    displacementZ = nextPos.z - intendedPos.z

    -- Only ledge grab if the wall displaced Mario in the opposite direction of
    -- his velocity.
    if displacementX * m.vel.x + displacementZ * m.vel.z > 0.0 then
        return 0
    end

    --! Since the search for floors starts at y + m.marioObj.hitboxHeight (160.0f), we will sometimes grab
    -- a higher ledge than expected (glitchy ledge grab)
    ledgePos.x = nextPos.x - wall.normal.x * 60.0
    ledgePos.z = nextPos.z - wall.normal.z * 60.0
    ledgePos.y = find_floor_height(ledgePos.x, nextPos.y + m.marioObj.hitboxHeight, ledgePos.z)

    ledgeFloor = collision_find_floor(ledgePos.x, ledgePos.y,ledgePos.z)
    if not ledgeFloor then return 0 end

    if gLevelValues.fixCollisionBugs ~= 0 and gLevelValues.fixCollisionBugsFalseLedgeGrab ~= 0 then
        -- fix false ledge grabs
        if (not ledgeFloor or ledgeFloor.normal.y < 0.90630779) then
            return 0
        end
    end

    if ledgePos.y - nextPos.y <= 100.0 then
        return 0
    end

    vec3f_copy(m.pos, ledgePos)
    m.floor = ledgeFloor
    m.floorHeight = ledgePos.y

    m.floorAngle = atan2s(ledgeFloor.normal.z, ledgeFloor.normal.x)

    m.faceAngle.x = 0
    m.faceAngle.y = atan2s(wall.normal.z, wall.normal.x) + 0x8000
    return 1
end

--- @param m MarioState
--- @param intendedPos Vec3f
--- @param stepArg integer
--- @return integer
function perform_air_quarter_step(m, intendedPos, stepArg)
    if not m then return 0 end
    local wallDYaw
    local nextPos = gVec3fZero()
    local lowerWcd = collision_get_temp_wall_collision_data()
    local upperWcd = collision_get_temp_wall_collision_data()
    local ceil
    local floor
    local ceilHeight
    local floorHeight
    local waterLevel

    vec3f_copy(nextPos, intendedPos)

    resolve_and_return_wall_collisions_data(nextPos, 150.0, 50.0, upperWcd)
    resolve_and_return_wall_collisions_data(nextPos, 30.0, 50.0, lowerWcd)

    floor = collision_find_floor(nextPos.x, nextPos.y, nextPos.z)
    floorHeight = find_floor_height(nextPos.x, nextPos.y, nextPos.z)
    ceil = collision_find_ceil(nextPos.x, floorHeight, nextPos.z)
    ceilHeight = vec3f_mario_ceil(nextPos, floorHeight)

    waterLevel = find_water_level(nextPos.x, nextPos.z)

    m.wall = nil

    --! The water pseudo floor is not referenced when your intended qstep is
    -- out of bounds, so it won't detect you as landing.

    if not floor then
        if nextPos.y <= m.floorHeight then
            m.pos.y = m.floorHeight
            return AIR_STEP_LANDED
        end

        m.pos.y = nextPos.y
        if gServerSettings.bouncyLevelBounds ~= BOUNCY_LEVEL_BOUNDS_OFF then
            m.faceAngle.y = m.faceAngle.y + 0x8000
            mario_set_forward_vel(m, gServerSettings.bouncyLevelBounds == BOUNCY_LEVEL_BOUNDS_ON_CAP and math.clamp(1.5 * m.forwardVel, -500, 500) or 1.5 * m.forwardVel)
        end
        return AIR_STEP_HIT_WALL
    end

    if (m.action & ACT_FLAG_RIDING_SHELL) ~= 0 and floorHeight < waterLevel then
        local allowForceAction = TRIPLET_BUTTERFLY_ACT_ACTIVATE
        if allowForceAction then
            floorHeight = waterLevel
            floor = get_water_surface_pseudo_floor()
            floor.originOffset = floorHeight
        end
    end

    --! This check uses f32, but findFloor uses short (overflow jumps)
    if nextPos.y <= floorHeight then
        if ceilHeight - floorHeight > m.marioObj.hitboxHeight then
            m.pos.x = nextPos.x
            m.pos.z = nextPos.z
            m.floor = floor
            m.floorHeight = floorHeight
        end

        --! When ceilHeight - floorHeight <= m->marioObj->hitboxHeight (160.0f), the step result says that
        -- Mario landed, but his movement is cancelled and his referenced floor
        -- isn't updated (pedro spots)
        m.pos.y = floorHeight
        return AIR_STEP_LANDED
    end

    if nextPos.y + m.marioObj.hitboxHeight > ceilHeight then
        if m.vel.y >= 0.0 then
            m.vel.y = 0.0

            --! Uses referenced ceiling instead of ceil (ceiling hang upwarp)
            if (stepArg and (stepArg & AIR_STEP_CHECK_HANG) ~= 0) and m.ceil and m.ceil.type == SURFACE_HANGABLE then
                return AIR_STEP_GRABBED_CEILING
            end

            return AIR_STEP_NONE
        end

        if nextPos.y <= m.floorHeight then
            m.pos.y = m.floorHeight
            return AIR_STEP_LANDED
        end

        m.pos.y = nextPos.y
        return AIR_STEP_HIT_WALL
    end

    --! When the wall is not completely vertical or there is a slight wall
    -- misalignment, you can activate these conditions in unexpected situations
    if (stepArg and (stepArg & AIR_STEP_CHECK_LEDGE_GRAB) ~= 0) and upperWcd.numWalls == 0 and lowerWcd.numWalls > 0 then
        for i = 1, lowerWcd.numWalls do
            if gLevelValues.fixCollisionBugs == 0 then
                i = lowerWcd.numWalls
            end
            local wall = lowerWcd.walls[i]
            if check_ledge_grab(m, wall, intendedPos, nextPos) ~= 0 then
                return AIR_STEP_GRABBED_LEDGE
            end
        end

        vec3f_copy(m.pos, nextPos)
        m.floor = floor
        m.floorHeight = floorHeight
        return AIR_STEP_NONE
    end

    vec3f_copy(m.pos, nextPos)
    m.floor = floor
    m.floorHeight = floorHeight

    if upperWcd.numWalls > 0 then
        mario_update_wall(m, upperWcd)

        for i = 1, upperWcd.numWalls do
            if gLevelValues.fixCollisionBugs == 0 then
                i = upperWcd.numWalls
            end

            local wall = upperWcd.walls[i]
            wallDYaw = atan2s(wall.normal.z, wall.normal.x) - m.faceAngle.y

            if wall.type == SURFACE_BURNING then
                m.wall = wall
                return AIR_STEP_HIT_LAVA_WALL
            end

            if wallDYaw < -0x6000 or wallDYaw > 0x6000 then
                m.wall = wall
                m.flags = m.flags | MARIO_UNKNOWN_30
                return AIR_STEP_HIT_WALL
            end
        end
    elseif lowerWcd.numWalls > 0 then
        mario_update_wall(m, lowerWcd)

        for i = 1, lowerWcd.numWalls do
            if gLevelValues.fixCollisionBugs == 0 then
                i = lowerWcd.numWalls
            end

            local wall = lowerWcd.walls[i]
            wallDYaw = atan2s(wall.normal.z, wall.normal.x) - m.faceAngle.y

            if wall.type == SURFACE_BURNING then
                m.wall = wall
                return AIR_STEP_HIT_LAVA_WALL
            end

            if wallDYaw < -0x6000 or wallDYaw > 0x6000 then
                m.wall = wall
                m.flags = m.flags | MARIO_UNKNOWN_30
                return AIR_STEP_HIT_WALL
            end
        end
    end

    return AIR_STEP_NONE
end

--- @param m MarioState
function apply_twirl_gravity(m)
    if not m then return end
    local terminalVelocity
    local heaviness = 1.0

    if m.angleVel.y > 1024 then
        heaviness = 1024.0 / m.angleVel.y
    end

    terminalVelocity = -75.0 * heaviness

    m.vel.y = m.vel.y - 4.0 * heaviness
    if m.vel.y < terminalVelocity then
        m.vel.y = terminalVelocity
    end
end

--- @param m MarioState
--- @return integer
function should_strengthen_gravity_for_jump_ascent(m)
    if not m then return 0 end
    if m.flags & MARIO_UNKNOWN_08 == 0 then
        return 0
    end

    if m.action & ACT_FLAG_INTANGIBLE ~= 0 or m.action & ACT_FLAG_INVULNERABLE ~= 0 then
        return 0
    end

    if m.input & INPUT_A_DOWN == 0 and m.vel.y > 20.0 then
        return m.action & ACT_FLAG_CONTROL_JUMP_HEIGHT ~= 0 and 1 or 0
    end

    return 0
end

--- @param m MarioState
function apply_gravity(m)
    if not m then return end

    if m.action == ACT_TWIRLING and m.vel.y < 0.0 then
        apply_twirl_gravity(m)
    elseif m.action == ACT_SHOT_FROM_CANNON then
        m.vel.y = m.vel.y - 1.0
        if m.vel.y < -75.0 then
            m.vel.y = -75.0
        end
    elseif m.action == ACT_LONG_JUMP or m.action == ACT_SLIDE_KICK or m.action == ACT_BBH_ENTER_SPIN then
        m.vel.y = m.vel.y - 2.0
        if m.vel.y < -75.0 then
            m.vel.y = -75.0
        end
    elseif m.action == ACT_LAVA_BOOST or m.action == ACT_FALL_AFTER_STAR_GRAB then
        m.vel.y = m.vel.y - 3.2
        if m.vel.y < -65.0 then
            m.vel.y = -65.0
        end
    elseif m.action == ACT_GETTING_BLOWN then
        m.vel.y = m.vel.y - m.unkC4
        if m.vel.y < -75.0 then
            m.vel.y = -75.0
        end
    elseif should_strengthen_gravity_for_jump_ascent(m) ~= 0 then
        m.vel.y = m.vel.y / 4.0
    elseif m.action & ACT_FLAG_METAL_WATER ~= 0 then
        m.vel.y = m.vel.y - 1.6
        if m.vel.y < -16.0 then
            m.vel.y = -16.0
        end
    elseif m.flags & MARIO_WING_CAP ~= 0 and m.vel.y < 0.0 and m.input & INPUT_A_DOWN ~= 0 then
        m.marioBodyState.wingFlutter = 1

        m.vel.y = m.vel.y - 2.0
        if m.vel.y < -37.5 then
            if (m.vel.y + 4.0) > -37.5 then
                m.vel.y = -37.5
            else
                m.vel.y = m.vel.y + 4.0
            end
        end
    else
        m.vel.y = m.vel.y - 4.0
        if m.vel.y < -75.0 then
            m.vel.y = -75.0
        end
    end
end

---@param m MarioState
function apply_vertical_wind(m)
    if not m then return end
    local maxVelY
    local offsetY
    local allowHazard = true
    if m.action ~= ACT_GROUND_POUND and allowHazard then
        offsetY = m.pos.y - -1500.0

        if m.floor and m.floor.type == SURFACE_VERTICAL_WIND and -3000.0 < offsetY and offsetY < 2000.0 then
            if offsetY >= 0.0 then
                maxVelY = 10000.0 / (offsetY + 200.0)
            else
                maxVelY = 50.0
            end

            if m.vel.y < maxVelY then
                if (m.vel.y + maxVelY / 8.0) > maxVelY then
                    m.vel.y = maxVelY
                end
            end

            if VERSION_REGION == "JP" then
                play_sound(SOUND_ENV_WIND2, m.marioObj.header.gfx.cameraToObject)
            end
        end
    end
end


gFindWallDirection = gVec3fZero()

--- @param m MarioState
--- @param stepArg integer
--- @return integer
function perform_custom_air_step(m, stepArg)
    local intendedPos = gVec3fZero()
    local quarterStepResult
    local stepResult = AIR_STEP_NONE

    m.wall = nil

    for i = 0, 4 do
        local step = gVec3fZero()
        step = {
            x = m.vel.x / 4.0,
            y = m.vel.y / 4.0,
            z = m.vel.z / 4.0,
        }

        intendedPos.x = m.pos.x + step.x
        intendedPos.y = m.pos.y + step.y
        intendedPos.z = m.pos.z + step.z

        vec3f_normalize(step)
        vec3f_copy(gFindWallDirection, step)

        gFindWallDirectionActive = true
        gFindWallDirectionAirborne = true
        quarterStepResult = perform_air_quarter_step(m, intendedPos, stepArg)
        gFindWallDirectionAirborne = false
        gFindWallDirectionActive = false

        --! On one qf, hit OOB/ceil/wall to store the 2 return value, and continue
        -- getting 0s until your last qf. Graze a wall on your last qf, and it will
        -- return the stored 2 with a sharply angled reference wall. (some gwks)

        if (quarterStepResult ~= AIR_STEP_NONE) then
            stepResult = quarterStepResult
        end

        if (quarterStepResult == AIR_STEP_LANDED or quarterStepResult == AIR_STEP_GRABBED_LEDGE
            or quarterStepResult == AIR_STEP_GRABBED_CEILING
            or quarterStepResult == AIR_STEP_HIT_LAVA_WALL) then
            break
        end
    end

    if (m.vel.y >= 0.0) then
        m.peakHeight = m.pos.y
    end

    m.terrainSoundAddend = mario_get_terrain_sound_addend(m)

    if (m.action ~= ACT_FLYING and m.action ~= ACT_BUBBLED) then
        apply_gravity(m)
    end
    apply_vertical_wind(m)

    vec3f_copy(m.marioObj.header.gfx.pos, m.pos)
    vec3s_set(m.marioObj.header.gfx.angle, 0, m.faceAngle.y, 0)

    return stepResult
end
