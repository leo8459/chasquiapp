<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        config(['mobile.required_version' => '1.0.5+6']);
        $this->withHeader('X-App-Version', '1.0.5+6');
    }
}
