@testsnippet SharedData begin
    sample_input = "Hello, World!"
    expected_output = "Hello, World!"
end

@testmodule CommonHelpers begin
    function is_valid_string(s)
        return isa(s, String) && !isempty(s)
    end
end

@testitem "Basic functionality test" tags = [:unit, :fast] setup = [SharedData] begin
    result = sample_input
    @test result == expected_output
    @test isa(result, String)
end

@testitem "Input validation test" tags = [:unit, :validation] setup = [CommonHelpers] begin
    result = "is a string"
    @test CommonHelpers.is_valid_string(result)
end

@testitem "Performance test" tags = [:integration, :slow] begin
    # Test that function executes quickly
    result = @timed "Hello, World!"
    @test result.time < 0.001  # Should complete in less than 1ms
    @test result.value == "Hello, World!"
end
